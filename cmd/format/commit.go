package format

import (
	"context"
	"errors"
	"fmt"
	"os"
	"slices"

	"github.com/amarbel-llc/conformist/config"
	"github.com/amarbel-llc/conformist/git"
	"github.com/amarbel-llc/conformist/stats"
	"github.com/amarbel-llc/conformist/walk"
	"github.com/charmbracelet/log"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

// CommitMessage is the conventional message for auto-applied fixes (#24).
const CommitMessage = "chore: conformist fmt+fix"

var (
	// ErrFixesCommitted signals that --commit applied fixes and created a
	// commit. Not a failure: it flows through the error channel so main can
	// map it to exit code 3, distinct from 0 (tree was already conformant),
	// 1 (findings / other errors) and 2 (refused or operational failure).
	ErrFixesCommitted = errors.New("fixes were applied and committed")

	// ErrCommitRefused indicates --commit declined to run (exit code 2):
	// outside a git worktree, in stdin mode, or on an unclean working tree
	// without --allow-dirty. Refusal happens BEFORE any formatting, so a
	// refused run leaves the tree untouched.
	ErrCommitRefused = errors.New("refusing to format and commit")
)

// CommitOptions carries the --commit flow's knobs from the CLI flags.
type CommitOptions struct {
	// AllowDirty admits an unclean working tree; pre-dirty files are excluded
	// from the fix commit.
	AllowDirty bool
	// Trailers are appended to the commit message via `git commit --trailer`
	// (#26), e.g. a tool-attribution line.
	Trailers []string
}

// RunCommit wraps Run with the --commit flow (#24): verify the tree is safe
// to auto-commit, format/repair in place, then commit exactly the files the
// run changed as a `chore: conformist fmt+fix` commit. git itself is the
// change detector — the pre/post `git status` delta — because the formatter
// pipeline's own change accounting does not see linter-repair writes.
func RunCommit(v *viper.Viper, statz *stats.Stats, cmd *cobra.Command, paths []string, opts CommitOptions) error {
	cmd.SilenceUsage = true

	cfg, err := config.FromViper(v)
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	ctx := cmd.Context()
	if ctx == nil {
		ctx = context.Background()
	}

	preDirty, err := commitPreflight(ctx, cfg, opts.AllowDirty)
	if err != nil {
		return err
	}

	if err := Run(v, statz, cmd, paths); err != nil {
		return err
	}

	post, err := git.ChangedPaths(ctx, cfg.TreeRoot)
	if err != nil {
		return fmt.Errorf("failed to detect changed files: %w", err)
	}

	// commit only files this run changed: anything dirty before the run
	// (admitted via --allow-dirty) is excluded, even if a formatter changed
	// it further — its diff would mix user work with fixes.
	toCommit := make([]string, 0, len(post))

	for _, p := range post {
		if !preDirty[p] {
			toCommit = append(toCommit, p)
		}
	}

	if len(toCommit) == 0 {
		log.Debugf("--commit: no fixes were needed")

		return nil
	}

	slices.Sort(toCommit)

	// A failed commit (e.g. the signing agent is locked) must fail loudly:
	// CommitPaths surfaces git's stderr, no commit is created, and the index
	// is left untouched (`git commit -- <paths>` stages nothing on failure).
	sha, err := git.CommitPaths(ctx, cfg.TreeRoot, CommitMessage, opts.Trailers, toCommit)
	if err != nil {
		return fmt.Errorf("failed to commit fixes: %w", err)
	}

	if !cfg.Quiet {
		fmt.Fprintf(os.Stderr, "committed %d fixed file(s) as %s (%s)\n", len(toCommit), sha, CommitMessage)
	}

	// ErrFixesCommitted is exit-code signalling (3), not a failure to print.
	cmd.SilenceErrors = true

	return ErrFixesCommitted
}

// commitPreflight enforces the --commit safety policy and returns the set of
// paths that were already dirty before the run. Current policy: refuse on ANY
// tracked staged/unstaged change unless --allow-dirty is passed (untracked
// files are ignored throughout — they are never committed).
//
// NOTE(#24, agent-loop): this policy is deliberately isolated here. It is a
// first cut optimized for the pre-merge-hook case, where the tree is clean by
// construction; once the flag has seen real agent-loop use the
// refuse/allow-dirty split may need revisiting (e.g. scoping dirtiness to
// formatter-matched files) without touching the commit flow itself.
func commitPreflight(ctx context.Context, cfg *config.Config, allowDirty bool) (map[string]bool, error) {
	if walkType, typeErr := walk.TypeString(cfg.Walk); typeErr == nil && walkType == walk.Stdin {
		return nil, fmt.Errorf("%w: stdin mode has no working tree state to commit", ErrCommitRefused)
	}

	// fail-on-change wants changes to fail the run; --commit wants them
	// committed. The cobra flag exclusion only catches the literal flag pair;
	// this catches it arriving via env, config, or --ci (which implies it) —
	// otherwise the run would format, error, and strand uncommitted fixes.
	if cfg.FailOnChange {
		return nil, fmt.Errorf(
			"%w: fail-on-change (implied by --ci) contradicts committing the changes", ErrCommitRefused,
		)
	}

	insideWorktree, err := git.IsInsideWorktree(cfg.TreeRoot)
	if err != nil {
		return nil, fmt.Errorf("failed to check for a git worktree: %w", err)
	}

	if !insideWorktree {
		return nil, fmt.Errorf("%w: %s is not inside a git worktree", ErrCommitRefused, cfg.TreeRoot)
	}

	dirty, err := git.ChangedPaths(ctx, cfg.TreeRoot)
	if err != nil {
		return nil, fmt.Errorf("failed to detect uncommitted changes: %w", err)
	}

	if len(dirty) > 0 && !allowDirty {
		return nil, fmt.Errorf(
			"%w: the working tree has uncommitted changes to %d tracked file(s); "+
				"commit or stash them, or pass --allow-dirty to commit only files this run changes",
			ErrCommitRefused, len(dirty),
		)
	}

	preDirty := make(map[string]bool, len(dirty))
	for _, p := range dirty {
		preDirty[p] = true
	}

	return preDirty, nil
}
