package cmd_test

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/amarbel-llc/conformist/cmd"
	formatCmd "github.com/amarbel-llc/conformist/cmd/format"
	"github.com/amarbel-llc/conformist/config"
	"github.com/amarbel-llc/conformist/test"
	"github.com/stretchr/testify/require"
)

// TestCommit covers the --commit flow (#24): after formatting, conformist
// stages exactly the files the run changed and creates a
// `chore: conformist fmt+fix` commit. Exit codes: 0 = tree was already
// conformant, 3 = fixes were applied and committed, 2 = refused (dirty tree,
// not a git worktree) or operational error.
func TestCommit(t *testing.T) {
	as := require.New(t)

	tempDir := test.TempExamples(t)
	configPath := filepath.Join(tempDir, "conformist.toml")

	test.ChangeWorkDir(t, tempDir)

	// Neutralize the developer/CI git config (commit signing, templates,
	// hooks) for both this test's git calls and the commit conformist
	// creates; identity comes from the explicit env below.
	t.Setenv("GIT_CONFIG_GLOBAL", "/dev/null")
	t.Setenv("GIT_CONFIG_SYSTEM", "/dev/null")
	t.Setenv("GIT_AUTHOR_NAME", "conformist-test")
	t.Setenv("GIT_AUTHOR_EMAIL", "conformist-test@example.invalid")
	t.Setenv("GIT_COMMITTER_NAME", "conformist-test")
	t.Setenv("GIT_COMMITTER_EMAIL", "conformist-test@example.invalid")

	git := func(args ...string) string {
		t.Helper()

		out, err := exec.CommandContext(t.Context(), "git", args...).CombinedOutput()
		as.NoError(err, "git %v: %s", args, out)

		return strings.TrimSpace(string(out))
	}

	// test-fmt-append always mutates its target, standing in for a formatter
	// that reflows a mis-formatted file.
	cfg := &config.Config{
		FormatterConfigs: map[string]*config.Formatter{
			"append": {
				Command:  "test-fmt-append",
				Options:  []string{"hello"},
				Includes: []string{"ruby/*"},
			},
		},
	}

	test.WriteConfig(t, configPath, cfg)

	// --commit outside a git worktree is refused (exit 2)
	conformist(t,
		withArgs("--commit"),
		withError(func(as *require.Assertions, err error) {
			as.ErrorIs(err, formatCmd.ErrCommitRefused)
			as.Equal(2, cmd.ExitCode(err))
		}),
	)

	// the refusal must happen before any formatting
	ruby, err := os.ReadFile("ruby/bundler.rb")
	as.NoError(err)
	as.NotContains(string(ruby), "hello")

	git("init")
	git("add", ".")
	git("commit", "-m", "init")

	headBefore := git("rev-parse", "HEAD")

	// a dirty tracked file refuses --commit (exit 2): no formatting, no commit
	mainGo := filepath.Join("go", "main.go")
	as.NoError(os.WriteFile(mainGo, []byte("package main\n"), 0o644))

	conformist(t,
		withArgs("--commit"),
		withError(func(as *require.Assertions, err error) {
			as.ErrorIs(err, formatCmd.ErrCommitRefused)
			as.Equal(2, cmd.ExitCode(err))
		}),
	)
	as.Equal(headBefore, git("rev-parse", "HEAD"))

	git("checkout", "--", mainGo)

	// clean tree: the reformatted file is committed, exit 3
	conformist(t,
		withArgs("--commit"),
		withError(func(as *require.Assertions, err error) {
			as.ErrorIs(err, formatCmd.ErrFixesCommitted)
			as.Equal(3, cmd.ExitCode(err))
		}),
	)

	headFixed := git("rev-parse", "HEAD")
	as.NotEqual(headBefore, headFixed, "a fix commit should have been created")
	as.Equal("chore: conformist fmt+fix", git("log", "-1", "--format=%s"))
	as.Equal("ruby/bundler.rb", git("show", "--name-only", "--format=", "HEAD"),
		"exactly the reformatted file should be committed")
	as.Empty(git("status", "--porcelain", "--untracked-files=no"),
		"the tracked tree should be clean after the fix commit")

	// second run: nothing left to fix (change detection skips the file),
	// exit 0, no new commit
	conformist(t,
		withArgs("--commit"),
		withNoError(t),
	)
	as.Equal(headFixed, git("rev-parse", "HEAD"))

	// --ci implies fail-on-change, which contradicts committing: refused
	// before any formatting (exit 2)
	conformist(t,
		withArgs("--commit", "--ci"),
		withError(func(as *require.Assertions, err error) {
			as.ErrorIs(err, formatCmd.ErrCommitRefused)
			as.Equal(2, cmd.ExitCode(err))
		}),
	)
	as.Equal(headFixed, git("rev-parse", "HEAD"))

	// --allow-dirty: an unrelated dirty file is excluded from the commit and
	// left dirty in the working tree (--no-cache forces a reformat of the
	// otherwise-skipped target)
	as.NoError(os.WriteFile(mainGo, []byte("package main\n"), 0o644))

	conformist(t,
		withArgs("--commit", "--allow-dirty", "--no-cache"),
		withError(func(as *require.Assertions, err error) {
			as.ErrorIs(err, formatCmd.ErrFixesCommitted)
			as.Equal(3, cmd.ExitCode(err))
		}),
	)

	as.Equal("ruby/bundler.rb", git("show", "--name-only", "--format=", "HEAD"),
		"the pre-existing dirty file must not be swept into the fix commit")
	// the helper trims the leading XY-column space from the porcelain output
	as.Equal("M go/main.go", git("status", "--porcelain", "--untracked-files=no"),
		"the pre-existing dirty file should remain dirty in the working tree")
}

// TestCommitStdin asserts --commit refuses stdin mode: there is no working
// tree state to commit when formatting a stream.
func TestCommitStdin(t *testing.T) {
	tempDir := test.TempExamples(t)
	configPath := filepath.Join(tempDir, "conformist.toml")

	test.ChangeWorkDir(t, tempDir)

	cfg := &config.Config{
		FormatterConfigs: map[string]*config.Formatter{
			"echo": {
				Command:  "echo",
				Includes: []string{"*"},
			},
		},
	}

	test.WriteConfig(t, configPath, cfg)

	conformist(t,
		withArgs("--commit", "--stdin", "ruby/bundler.rb"),
		withError(func(as *require.Assertions, err error) {
			as.Error(err)
			as.Equal(2, cmd.ExitCode(err))
		}),
	)
}
