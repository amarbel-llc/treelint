package format_test

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/amarbel-llc/treelint/config"
	"github.com/amarbel-llc/treelint/format"
	"github.com/amarbel-llc/treelint/stats"
	"github.com/amarbel-llc/treelint/walk"
	"github.com/stretchr/testify/require"
)

func writeFile(t *testing.T, root, rel, content string, mode os.FileMode) string {
	t.Helper()

	path := filepath.Join(root, rel)
	require.NoError(t, os.MkdirAll(filepath.Dir(path), 0o755))
	require.NoError(t, os.WriteFile(path, []byte(content), mode))

	return path
}

func walkFile(t *testing.T, root, rel string) *walk.File {
	t.Helper()

	info, err := os.Stat(filepath.Join(root, rel))
	require.NoError(t, err)

	return &walk.File{Path: filepath.Join(root, rel), RelPath: rel, Info: info}
}

// TestCompositeCheckerLinterFindings verifies that a linter's non-zero exit is
// surfaced as a lint finding and a clean run is not.
func TestCompositeCheckerLinterFindings(t *testing.T) {
	as := require.New(t)
	root := t.TempDir()

	// stub linter: exit 1 if any passed file contains the marker "BAD".
	lint := writeFile(t, root, "lint.sh",
		"#!/usr/bin/env bash\nfor f in \"$@\"; do grep -q BAD \"$f\" && exit 1; done\nexit 0\n", 0o755)

	writeFile(t, root, "good.sh", "echo ok\n", 0o644)
	writeFile(t, root, "bad.sh", "echo BAD\n", 0o644)

	statz := stats.New()

	cfg := &config.Config{
		TreeRoot:    root,
		OnUnmatched: "info",
		LinterConfigs: map[string]*config.Linter{
			"stub": {Command: lint, Includes: []string{"*.sh"}},
		},
	}

	checker, err := format.NewCompositeChecker(cfg, &statz)
	as.NoError(err)

	findings, err := checker.Check(context.Background(), []*walk.File{
		walkFile(t, root, "good.sh"),
		walkFile(t, root, "bad.sh"),
	})
	as.NoError(err)
	as.Len(findings, 1)
	as.Equal(format.FindingLint, findings[0].Kind)
	as.Equal("stub", findings[0].Tool)
}

// TestCompositeCheckerSandbox verifies that a fix-only formatter is checked via
// the sandbox: a file that would change is reported, and the original is never
// modified on disk.
func TestCompositeCheckerSandbox(t *testing.T) {
	as := require.New(t)
	root := t.TempDir()

	// stub fix-only formatter: append a trailing newline if one is missing.
	// The explicit `exit 0` keeps the script's status zero even when the last
	// file needs no change (otherwise the trailing test would set status 1).
	fix := writeFile(t, root, "fix.sh",
		"#!/usr/bin/env bash\nfor f in \"$@\"; do [ -n \"$(tail -c1 \"$f\")\" ] && printf '\\n' >> \"$f\"; done\nexit 0\n", 0o755)

	writeFile(t, root, "needs.txt", "no-trailing-newline", 0o644)
	writeFile(t, root, "ok.txt", "already-fine\n", 0o644)

	statz := stats.New()

	cfg := &config.Config{
		TreeRoot:    root,
		OnUnmatched: "info",
		FormatterConfigs: map[string]*config.Formatter{
			"stub": {Command: fix, Includes: []string{"*.txt"}},
		},
	}

	checker, err := format.NewCompositeChecker(cfg, &statz)
	as.NoError(err)

	before, err := os.ReadFile(filepath.Join(root, "needs.txt"))
	as.NoError(err)

	findings, err := checker.Check(context.Background(), []*walk.File{
		walkFile(t, root, "needs.txt"),
		walkFile(t, root, "ok.txt"),
	})
	as.NoError(err)

	as.Len(findings, 1)
	as.Equal(format.FindingFormat, findings[0].Kind)
	as.Equal("needs.txt", findings[0].Path)

	// the sandbox must never write the original file
	after, err := os.ReadFile(filepath.Join(root, "needs.txt"))
	as.NoError(err)
	as.Equal(string(before), string(after))
}
