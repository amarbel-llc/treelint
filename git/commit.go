package git

import (
	"context"
	"fmt"
	"os/exec"
	"strings"
)

// StatusEntry is one `git status --porcelain` row for a tracked path: Staged
// is the index (X) column, Unstaged the worktree (Y) column.
type StatusEntry struct {
	Staged   byte
	Unstaged byte
	Path     string
}

// StatusEntries returns the tracked paths with staged or unstaged changes, as
// reported by `git status --porcelain -z --untracked-files=no`,
// toplevel-relative. Untracked files are excluded by design: neither the
// --commit (#24) nor the --staged (#25) flow touches paths git does not
// already track.
func StatusEntries(ctx context.Context, treeRoot string) ([]StatusEntry, error) {
	cmd := exec.CommandContext(ctx, "git", "-C", treeRoot, "status", "--porcelain", "-z", "--untracked-files=no")

	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("failed to read git status for %s: %w", treeRoot, err)
	}

	var entries []StatusEntry

	// -z entries are "XY <path>" separated by NUL; a rename/copy ("R"/"C" in
	// the staged column) is followed by its origin path as an extra NUL field,
	// which we skip — the current path is what a fix would operate on.
	fields := strings.Split(string(out), "\x00")
	for i := 0; i < len(fields); i++ {
		entry := fields[i]
		if len(entry) < 4 {
			continue
		}

		entries = append(entries, StatusEntry{
			Staged:   entry[0],
			Unstaged: entry[1],
			Path:     entry[3:],
		})

		if entry[0] == 'R' || entry[0] == 'C' {
			i++
		}
	}

	return entries, nil
}

// ChangedPaths returns the toplevel-relative paths of tracked files with
// staged or unstaged changes. See StatusEntries.
func ChangedPaths(ctx context.Context, treeRoot string) ([]string, error) {
	entries, err := StatusEntries(ctx, treeRoot)
	if err != nil {
		return nil, err
	}

	paths := make([]string, 0, len(entries))
	for _, entry := range entries {
		paths = append(paths, entry.Path)
	}

	return paths, nil
}

// AddPaths stages the given toplevel-relative paths (`git add`), anchored to
// the repository toplevel via the ":(top)" pathspec magic like CommitPaths.
func AddPaths(ctx context.Context, treeRoot string, paths []string) error {
	args := make([]string, 0, 4+len(paths))
	args = append(args, "-C", treeRoot, "add", "--")

	for _, p := range paths {
		args = append(args, ":(top)"+p)
	}

	cmd := exec.CommandContext(ctx, "git", args...)
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("git add failed: %w: %s", err, out)
	}

	return nil
}

// CommitPaths creates a commit containing exactly the given toplevel-relative
// paths, taking their content from the working tree (`git commit -- <paths>`).
// Unrelated staged changes are left in the index untouched. Invoking the real
// git binary means the repo's commit-signing and identity config are honored.
// Each trailer is appended to the message via `git commit --trailer`, which
// also validates it (a malformed trailer fails the commit). Returns the new
// commit's hash.
func CommitPaths(
	ctx context.Context,
	treeRoot string,
	message string,
	trailers []string,
	paths []string,
) (string, error) {
	args := make([]string, 0, 7+2*len(trailers)+len(paths))
	args = append(args, "-C", treeRoot, "commit", "--quiet", "-m", message)

	for _, trailer := range trailers {
		args = append(args, "--trailer", trailer)
	}

	args = append(args, "--")
	// the ":(top)" pathspec magic anchors each path to the repository
	// toplevel, matching the paths ChangedPaths reports even when treeRoot is
	// a subdirectory of the repository.
	for _, p := range paths {
		args = append(args, ":(top)"+p)
	}

	commitCmd := exec.CommandContext(ctx, "git", args...)
	if out, err := commitCmd.CombinedOutput(); err != nil {
		return "", fmt.Errorf("git commit failed: %w: %s", err, out)
	}

	revCmd := exec.CommandContext(ctx, "git", "-C", treeRoot, "rev-parse", "HEAD")

	out, err := revCmd.Output()
	if err != nil {
		return "", fmt.Errorf("failed to resolve the created commit: %w", err)
	}

	return strings.TrimSpace(string(out)), nil
}
