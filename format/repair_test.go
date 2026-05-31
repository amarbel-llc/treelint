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

// TestCompositeLinterRepair verifies that a linter with a repair command applies
// its autofix to matched files.
func TestCompositeLinterRepair(t *testing.T) {
	as := require.New(t)
	root := t.TempDir()

	// stub repair tool: rewrite the marker "BAD" to "GOOD" in each file.
	fix := writeFile(t, root, "fix.sh",
		"#!/usr/bin/env bash\nfor f in \"$@\"; do sed -i 's/BAD/GOOD/g' \"$f\"; done\n", 0o755)

	writeFile(t, root, "a.sh", "echo BAD\n", 0o644)

	statz := stats.New()

	cfg := &config.Config{
		TreeRoot:    root,
		OnUnmatched: "info",
		LinterConfigs: map[string]*config.Linter{
			// a check command is required by the schema; `true` is a no-op check.
			"stub": {Command: "true", Includes: []string{"*.sh"}, RepairCommand: fix},
		},
	}

	linter, err := format.NewCompositeLinter(cfg, &statz)
	as.NoError(err)
	as.False(linter.Empty())

	as.NoError(linter.Repair(context.Background(), []*walk.File{walkFile(t, root, "a.sh")}))

	got, err := os.ReadFile(filepath.Join(root, "a.sh"))
	as.NoError(err)
	as.Equal("echo GOOD\n", string(got))
}

// TestCompositeLinterEmptyWithoutRepair verifies that check-only linters are
// excluded from the repair-mode set (no autofix to apply).
func TestCompositeLinterEmptyWithoutRepair(t *testing.T) {
	as := require.New(t)
	root := t.TempDir()

	statz := stats.New()

	cfg := &config.Config{
		TreeRoot:    root,
		OnUnmatched: "info",
		LinterConfigs: map[string]*config.Linter{
			"checkonly": {Command: "true", Includes: []string{"*.sh"}},
		},
	}

	linter, err := format.NewCompositeLinter(cfg, &statz)
	as.NoError(err)
	as.True(linter.Empty())
}
