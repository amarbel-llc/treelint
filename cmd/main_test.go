package cmd_test

import (
	"os"
	"path/filepath"
	"testing"
)

// TestMain bounds both git tree-root resolution and conformist's own config
// discovery to the temp root for the whole cmd test package (conformist#15).
//
// The integration tests run conformist against fixtures created under $TMPDIR
// (test.TempExamples -> t.TempDir()). When $TMPDIR is itself inside a git
// worktree / monorepo — as in a spinclass session, where $TMPDIR is the
// worktree's .tmp/ — conformist would otherwise escape the (non-git) fixture
// two ways: `git rev-parse --show-toplevel` ascends into the worktree's .git,
// and config.FindUp walks all the way to / and picks up an ancestor
// conformist.toml/treelint.toml (e.g. the monorepo's). Either makes conformist
// treat real tracked files as its tree and run formatters over them. A normal
// $TMPDIR=/tmp has no ancestor repo or config, which is why this is otherwise
// masked.
//
// GIT_CEILING_DIRECTORIES bounds the git subprocess; CONFORMIST_CEILING_DIRECTORIES
// bounds config.FindUp. Setting both to the temp root stops each search there, so
// neither can reach the worktree. Fixtures that need a repo `git init` below the
// ceiling, so they still resolve to their own repo/config. EvalSymlinks to match
// the canonical comparison git and conformist both do.
func TestMain(m *testing.M) {
	if tmp, err := filepath.EvalSymlinks(os.TempDir()); err == nil {
		for _, key := range []string{
			"GIT_CEILING_DIRECTORIES",
			"CONFORMIST_CEILING_DIRECTORIES",
		} {
			// Don't clobber an explicit ceiling the environment already set.
			if os.Getenv(key) == "" {
				_ = os.Setenv(key, tmp)
			}
		}
	}

	os.Exit(m.Run())
}
