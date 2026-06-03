package format

import (
	"context"
	"errors"
	"fmt"
	"os"

	"github.com/amarbel-llc/conformist/config"
	"github.com/amarbel-llc/conformist/stats"
	"github.com/amarbel-llc/conformist/walk"
	"github.com/charmbracelet/log"
	"github.com/gobwas/glob"
	"mvdan.cc/sh/v3/expand"
)

// FindingKind distinguishes a formatting finding (a formatter would change the
// file) from a lint finding (a linter reported a problem).
type FindingKind string

const (
	FindingFormat FindingKind = "format"
	FindingLint   FindingKind = "lint"
)

// Finding records a single check result: a tool reported that something is not
// conformant. Path is set for formatter findings; linter findings are reported
// at the tool (invocation) level since linters do not attribute per file.
type Finding struct {
	Tool string
	Kind FindingKind
	Path string
}

// CompositeChecker runs formatters and linters in read-only check mode (RFC 0001
// §5). It never writes to the tree root.
type CompositeChecker struct {
	cfg            *config.Config
	stats          *stats.Stats
	globalExcludes []glob.Glob
	unmatchedLevel log.Level

	formatters map[string]*Formatter
	linters    map[string]*Linter
}

// Check evaluates the given files, returning the findings discovered. A non-nil
// error indicates an operational failure (RFC 0001 §7 error class), not findings.
func (c *CompositeChecker) Check(ctx context.Context, files []*walk.File) ([]Finding, error) {
	formatterFiles := map[*Formatter][]*walk.File{}
	linterFiles := map[*Linter][]*walk.File{}

	for _, file := range files {
		if pathMatches(file.RelPath, c.globalExcludes) {
			continue
		}

		matched := false

		for _, f := range c.formatters {
			if f.Wants(file) {
				formatterFiles[f] = append(formatterFiles[f], file)
				matched = true
			}
		}

		for _, l := range c.linters {
			if l.Wants(file) {
				linterFiles[l] = append(linterFiles[l], file)
				matched = true
			}
		}

		if matched {
			c.stats.Add(stats.Matched, 1)
		} else if c.unmatchedLevel == log.FatalLevel {
			return nil, fmt.Errorf("no formatter or linter for path: %s", file.RelPath)
		} else {
			log.Logf(c.unmatchedLevel, "no formatter or linter for path: %s", file.RelPath)
		}
	}

	var findings []Finding

	for f, fs := range formatterFiles {
		// Progress output: a fix-only formatter checked via sandbox-and-diff
		// can run for a long time over a large file set with no other signal,
		// making a slow run indistinguishable from a hang. Announce each
		// formatter (and its file count) before it runs so -v surfaces which
		// tool is active. Per-phase (copy vs. run) detail is logged at -vv in
		// checkSandbox.
		log.Infof("checking %d files with formatter %q", len(fs), f.Name())

		found, err := f.check(ctx, c.cfg.TreeRoot, fs)
		if err != nil {
			return nil, err
		}

		log.Debugf("formatter %q: %d findings", f.Name(), len(found))

		findings = append(findings, found...)
	}

	for l, fs := range linterFiles {
		log.Infof("checking %d files with linter %q", len(fs), l.Name())

		hasFindings, output, err := l.Check(ctx, fs)
		if err != nil {
			return nil, err
		}

		if hasFindings {
			if output != "" {
				fmt.Fprintln(os.Stderr, output)
			}

			findings = append(findings, Finding{Tool: l.Name(), Kind: FindingLint})
		}
	}

	return findings, nil
}

// NewCompositeChecker builds a checker from config, initialising the configured
// formatters and linters.
func NewCompositeChecker(cfg *config.Config, statz *stats.Stats) (*CompositeChecker, error) {
	globalExcludes, err := compileGlobs(cfg.Excludes)
	if err != nil {
		return nil, fmt.Errorf("failed to compile global excludes: %w", err)
	}

	unmatchedLevel, err := log.ParseLevel(cfg.OnUnmatched)
	if err != nil {
		return nil, fmt.Errorf("invalid on-unmatched value: %w", err)
	}

	env := expand.ListEnviron(os.Environ()...)

	formatters := map[string]*Formatter{}

	for name, fCfg := range cfg.FormatterConfigs {
		formatter, err := newFormatter(name, cfg.TreeRoot, env, fCfg)
		if errors.Is(err, ErrCommandNotFound) && cfg.AllowMissingFormatter {
			log.Debugf("formatter command not found: %v", name)

			continue
		} else if err != nil {
			return nil, fmt.Errorf("failed to initialise formatter %v: %w", name, err)
		}

		formatters[name] = formatter
	}

	linters := map[string]*Linter{}

	for name, lCfg := range cfg.LinterConfigs {
		linter, err := newLinter(name, cfg.TreeRoot, env, lCfg)
		if errors.Is(err, ErrCommandNotFound) && cfg.AllowMissingFormatter {
			log.Debugf("linter command not found: %v", name)

			continue
		} else if err != nil {
			return nil, fmt.Errorf("failed to initialise linter %v: %w", name, err)
		}

		linters[name] = linter
	}

	return &CompositeChecker{
		cfg:            cfg,
		stats:          statz,
		globalExcludes: globalExcludes,
		unmatchedLevel: unmatchedLevel,
		formatters:     formatters,
		linters:        linters,
	}, nil
}
