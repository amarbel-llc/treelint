package cmd

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/amarbel-llc/treelint/cmd/format"
	_init "github.com/amarbel-llc/treelint/cmd/init"
	"github.com/amarbel-llc/treelint/config"
	"github.com/amarbel-llc/treelint/stats"
	"github.com/charmbracelet/log"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

// programName is the binary's self-identification, used in usage and version
// output. The broader treefmt -> treelint user-facing rename (TREEFMT_ env
// prefix, treefmt.toml config filenames, docs) is tracked separately.
const programName = "treelint"

func NewRoot(version, commit string) (*cobra.Command, *stats.Stats) {
	// create a viper instance for reading in config
	v, err := config.NewViper()
	if err != nil {
		cobra.CheckErr(fmt.Errorf("failed to create viper instance: %w", err))
	}

	// create a new stats instance
	statz := stats.New()

	// create our root command
	cmd := &cobra.Command{
		Use:     programName + " <paths...>",
		Short:   "The linter and formatter multiplexer",
		Version: version + "+" + commit,
		CompletionOptions: cobra.CompletionOptions{
			DisableDefaultCmd: true,
		},
		RunE: func(cmd *cobra.Command, args []string) error {
			return runE(v, &statz, cmd, args)
		},
	}

	// update version template
	cmd.SetVersionTemplate(programName + " {{.Version}}\n")

	// Config flags live on persistent flags so subcommands (e.g. `check`)
	// inherit the same tree-root / walk / excludes / config-file options.
	pfs := cmd.PersistentFlags()
	config.SetFlags(pfs)

	// xor tree-root, tree-root-cmd and tree-root-file flags
	cmd.MarkFlagsMutuallyExclusive(
		"tree-root",
		"tree-root-cmd",
		"tree-root-file",
	)

	pfs.String(
		"config-file", "",
		"Load the config file from the given path (defaults to searching upwards for treelint.toml or "+
			".treelint.toml).",
	)

	// Root-only shortcut flags for the init / completion sub-behaviours.
	fs := cmd.Flags()

	fs.BoolP(
		"init", "i", false,
		"Create a treelint.toml file in the current directory.",
	)

	fs.String(
		"completion", "",
		"[bash|zsh|fish] Generate shell completion scripts for the specified shell.",
	)

	// bind our config flags to viper
	if err := v.BindPFlags(pfs); err != nil {
		cobra.CheckErr(fmt.Errorf("failed to bind config flags to viper: %w", err))
	}

	// bind prj_root to the tree-root flag, allowing viper to handle environment override for us
	// conforms with https://github.com/numtide/prj-spec/blob/main/PRJ_SPEC.md
	cobra.CheckErr(v.BindPFlag("prj_root", pfs.Lookup("tree-root")))

	cmd.AddCommand(newCheckCmd(v, &statz))
	cmd.AddCommand(newVersionCmd(programName, version, commit))

	return cmd, &statz
}

// changeWorkingDir resolves and changes to the configured working directory,
// returning its absolute path. Shared by the format and check entry points.
func changeWorkingDir(v *viper.Viper) (string, error) {
	workingDir, err := filepath.Abs(v.GetString("working-dir"))
	if err != nil {
		return "", fmt.Errorf("failed to get absolute path for working directory: %w", err)
	}

	if err = os.Chdir(workingDir); err != nil {
		return "", fmt.Errorf("failed to change working directory: %w", err)
	}

	return workingDir, nil
}

func runE(v *viper.Viper, statz *stats.Stats, cmd *cobra.Command, args []string) error {
	flags := cmd.Flags()

	workingDir, err := changeWorkingDir(v)
	if err != nil {
		return err
	}

	// check if we are running the init command
	if init, err := flags.GetBool("init"); err != nil {
		return fmt.Errorf("failed to read init flag: %w", err)
	} else if init {
		if initErr := _init.Run(); initErr != nil {
			return fmt.Errorf("failed to run init command: %w", initErr)
		}

		return nil
	}

	// check if we are running the completion command
	if shell, err := flags.GetString("completion"); err != nil {
		return fmt.Errorf("failed to read completion flag: %w", err)
	} else if shell != "" {
		if completionsErr := generateShellCompletions(cmd, []string{shell}); completionsErr != nil {
			return fmt.Errorf("failed to generate shell completions: %w", completionsErr)
		}

		return nil
	}

	if err := loadConfig(v, cmd, workingDir); err != nil {
		return err
	}

	// format
	return format.Run(v, statz, cmd, args) //nolint:wrapcheck
}

// loadConfig discovers and reads the treelint config file into viper and
// configures logging. It assumes the working directory has already been set
// (see changeWorkingDir) and is shared by the format and check entry points.
func loadConfig(v *viper.Viper, cmd *cobra.Command, workingDir string) error {
	flags := cmd.Flags()

	// use the path specified by the flag
	configFile, err := flags.GetString("config-file")
	if err != nil {
		return fmt.Errorf("failed to read config-file flag: %w", err)
	}

	// fallback to env
	if configFile == "" {
		configFile = os.Getenv("TREELINT_CONFIG")
	}

	filenames := []string{"treelint.toml", ".treelint.toml"}

	// look in PRJ_ROOT if set
	if prjRoot := os.Getenv("PRJ_ROOT"); configFile == "" && prjRoot != "" {
		configFile, _ = config.Find(prjRoot, filenames...)
	}

	// search up from the working directory
	if configFile == "" {
		configFile, _, err = config.FindUp(workingDir, filenames...)
	}

	// error out if we couldn't find the config file
	if err != nil {
		cmd.SilenceUsage = true

		return fmt.Errorf("failed to find treelint config file: %w", err)
	}

	log.Debugf("using config file: %s", configFile)

	// read in the config
	v.SetConfigFile(configFile)

	if err := v.ReadInConfig(); err != nil {
		cobra.CheckErr(fmt.Errorf("failed to read config file '%s': %w", configFile, err))
	}

	// configure logging
	log.SetOutput(os.Stderr)
	log.SetReportTimestamp(false)

	if v.GetBool("quiet") {
		// if quiet, we only log errors
		log.SetLevel(log.ErrorLevel)
	} else {
		// otherwise, the verbose flag controls the log level
		switch v.GetInt("verbose") {
		case 0:
			log.SetLevel(log.WarnLevel)
		case 1:
			log.SetLevel(log.InfoLevel)
		default:
			log.SetLevel(log.DebugLevel)
		}
	}

	return nil
}
