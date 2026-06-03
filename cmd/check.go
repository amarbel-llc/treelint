package cmd

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/amarbel-llc/conformist/config"
	"github.com/amarbel-llc/conformist/format"
	"github.com/amarbel-llc/conformist/stats"
	"github.com/amarbel-llc/conformist/walk"
	"github.com/charmbracelet/log"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

// ErrCheckFindings indicates `conformist check` found at least one finding
// (RFC 0001 §7, exit code 1). ErrCheckOperational indicates an operational
// failure such as a missing executable or invalid config (exit code 2).
var (
	ErrCheckFindings    = errors.New("one or more findings were detected")
	ErrCheckOperational = errors.New("check failed")
)

// ExitCode maps a command error to a process exit code. The `check` subcommand
// distinguishes findings (1) from operational failures (2) per RFC 0001 §7; all
// other errors exit 1.
func ExitCode(err error) int {
	switch {
	case err == nil:
		return 0
	case errors.Is(err, ErrCheckFindings):
		return 1
	case errors.Is(err, ErrCheckOperational):
		return 2
	default:
		return 1
	}
}

func newCheckCmd(v *viper.Viper, statz *stats.Stats) *cobra.Command {
	return &cobra.Command{
		Use:   "check [paths...]",
		Short: "Check formatting and run linters without modifying any files",
		Long: "Evaluate every configured formatter and linter in read-only check mode. " +
			"Formatters with a native check command are run directly; fix-only formatters are " +
			"checked via a sandbox copy so the working tree is never written. Exits 0 when clean, " +
			"1 when findings are detected, and 2 on an operational error.",
		RunE: func(cmd *cobra.Command, args []string) error {
			return runCheck(v, statz, cmd, args)
		},
	}
}

func runCheck(v *viper.Viper, statz *stats.Stats, cmd *cobra.Command, paths []string) error {
	cmd.SilenceUsage = true

	workingDir, err := changeWorkingDir(v)
	if err != nil {
		return err
	}

	if err := loadConfig(v, cmd, workingDir); err != nil {
		return err
	}

	cfg, err := config.FromViper(v)
	if err != nil {
		return fmt.Errorf("%w: failed to load config: %w", ErrCheckOperational, err)
	}

	walkType, err := walk.TypeString(cfg.Walk)
	if err != nil {
		return fmt.Errorf("%w: invalid walk type: %w", ErrCheckOperational, err)
	}

	checker, err := format.NewCompositeChecker(cfg, statz)
	if err != nil {
		return fmt.Errorf("%w: failed to create checker: %w", ErrCheckOperational, err)
	}

	// read-only: pass a nil cache db so nothing is written.
	walker, err := walk.NewCompositeReader(walkType, cfg.TreeRoot, paths, nil, statz)
	if err != nil {
		return fmt.Errorf("%w: failed to create walker: %w", ErrCheckOperational, err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	go func() {
		exit := make(chan os.Signal, 1)
		signal.Notify(exit, os.Interrupt, syscall.SIGTERM)
		<-exit
		cancel()
	}()

	files := make([]*walk.File, format.BatchSize)

	var (
		findings []format.Finding
		readErr  error
	)

	for {
		readCtx, cancelRead := context.WithTimeout(ctx, 10*time.Second)
		n, rErr := walker.Read(readCtx, files)
		cancelRead()

		readErr = rErr

		batch := files[:n]

		batchFindings, checkErr := checker.Check(ctx, batch)
		if checkErr != nil {
			_ = walker.Close()

			return fmt.Errorf("%w: %w", ErrCheckOperational, checkErr)
		}

		findings = append(findings, batchFindings...)

		// release the batch; check mode never updates the cache
		releaseCtx := walk.SetNoCache(ctx, true)
		for _, file := range batch {
			if releaseErr := file.Release(releaseCtx); releaseErr != nil {
				_ = walker.Close()

				return fmt.Errorf("%w: failed to release file: %w", ErrCheckOperational, releaseErr)
			}
		}

		if readErr != nil {
			break
		}
	}

	if closeErr := walker.Close(); closeErr != nil {
		return fmt.Errorf("%w: failed to close walker: %w", ErrCheckOperational, closeErr)
	}

	switch {
	case readErr == nil, errors.Is(readErr, io.EOF):
		// nothing more to read
	case errors.Is(readErr, context.Canceled):
		log.Debugf("context cancelled")
	case errors.Is(readErr, context.DeadlineExceeded):
		return fmt.Errorf("%w: timeout reading files", ErrCheckOperational)
	default:
		return fmt.Errorf("%w: failed to read files: %w", ErrCheckOperational, readErr)
	}

	if !cfg.Quiet {
		statz.PrintToStderr()
	}

	if len(findings) > 0 {
		reportFindings(findings)

		return ErrCheckFindings
	}

	return nil
}

func reportFindings(findings []format.Finding) {
	for _, f := range findings {
		switch f.Kind {
		case format.FindingFormat:
			if f.Path != "" {
				fmt.Fprintf(os.Stdout, "would reformat: %s (%s)\n", f.Path, f.Tool)
			} else {
				fmt.Fprintf(os.Stdout, "formatting needed (%s)\n", f.Tool)
			}
		case format.FindingLint:
			fmt.Fprintf(os.Stdout, "lint findings (%s)\n", f.Tool)
		}
	}
}
