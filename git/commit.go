package git

import (
	"context"
	"fmt"
	"os/exec"
	"strings"
)

// ChangedPaths returns the toplevel-relative paths of tracked files with
// staged or unstaged changes, as reported by
// `git status --porcelain -z --untracked-files=no`. Untracked files are
// excluded by design: the --commit flow (#24) never stages paths git does not
// already track.
func ChangedPaths(ctx context.Context, treeRoot string) ([]string, error) {
	cmd := exec.CommandContext(ctx, "git", "-C", treeRoot, "status", "--porcelain", "-z", "--untracked-files=no")

	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("failed to read git status for %s: %w", treeRoot, err)
	}

	var paths []string

	// -z entries are "XY <path>" separated by NUL; a rename/copy ("R"/"C" in
	// the staged column) is followed by its origin path as an extra NUL field,
	// which we skip — the current path is what a fix commit would contain.
	fields := strings.Split(string(out), "\x00")
	for i := 0; i < len(fields); i++ {
		entry := fields[i]
		if len(entry) < 4 {
			continue
		}

		paths = append(paths, entry[3:])

		if entry[0] == 'R' || entry[0] == 'C' {
			i++
		}
	}

	return paths, nil
}

// CommitPaths creates a commit containing exactly the given toplevel-relative
// paths, taking their content from the working tree (`git commit -- <paths>`).
// Unrelated staged changes are left in the index untouched. Invoking the real
// git binary means the repo's commit-signing and identity config are honored.
// Returns the new commit's hash.
func CommitPaths(ctx context.Context, treeRoot string, message string, paths []string) (string, error) {
	args := make([]string, 0, 7+len(paths))
	args = append(args, "-C", treeRoot, "commit", "--quiet", "-m", message, "--")
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
