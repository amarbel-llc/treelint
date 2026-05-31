package format

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/amarbel-llc/treelint/walk"
)

// check evaluates a formatter in read-only mode and returns findings for the
// files it would change. It uses the native check command when configured (and
// sandbox is not forced), otherwise the sandbox-and-diff strategy (RFC 0001 §3).
func (f *Formatter) check(ctx context.Context, treeRoot string, files []*walk.File) ([]Finding, error) {
	if !f.config.Sandbox && f.config.CheckCommand != "" {
		nonzero, output, err := f.checkNative(ctx, files)
		if err != nil {
			return nil, err
		}

		if nonzero {
			if output != "" {
				fmt.Fprintln(os.Stderr, output)
			}

			// a native check reports at the invocation level, not per file
			return []Finding{{Tool: f.Name(), Kind: FindingFormat}}, nil
		}

		return nil, nil
	}

	changed, err := f.checkSandbox(ctx, treeRoot, files)
	if err != nil {
		return nil, err
	}

	findings := make([]Finding, 0, len(changed))
	for _, file := range changed {
		findings = append(findings, Finding{Tool: f.Name(), Kind: FindingFormat, Path: file.RelPath})
	}

	return findings, nil
}

// checkNative runs the formatter's configured read-only check command. It
// returns true if the command exited non-zero (at least one file is not
// conformant); a non-nil error indicates an operational failure.
func (f *Formatter) checkNative(ctx context.Context, files []*walk.File) (nonzero bool, output string, err error) {
	if len(files) == 0 {
		return false, "", nil
	}

	maxBatch := len(files)
	if f.HasNoPositionalArgSupport() {
		maxBatch = 1
	}

	var combined strings.Builder

	for start := 0; start < len(files); start += maxBatch {
		end := min(start+maxBatch, len(files))

		args := append([]string{}, f.config.CheckOptions...)
		for _, file := range files[start:end] {
			args = append(args, file.RelPath)
		}

		cmd := exec.CommandContext(ctx, f.checkExecutable, args...) //nolint:gosec
		cmd.Cancel = func() error { return cmd.Process.Signal(os.Interrupt) }
		cmd.Dir = f.workingDir

		out, runErr := cmd.CombinedOutput()
		combined.Write(out)

		if runErr != nil {
			var exitErr *exec.ExitError
			if errors.As(runErr, &exitErr) {
				nonzero = true

				continue
			}

			return false, combined.String(), fmt.Errorf("formatter '%s' check command failed: %w", f.name, runErr)
		}
	}

	return nonzero, combined.String(), nil
}

// checkSandbox synthesizes a read-only check for a fix-only formatter (RFC 0001
// §6): it copies the matched files into a private temp dir, runs the formatter's
// repair command there, and reports which files the formatter would change. The
// original files are never written.
func (f *Formatter) checkSandbox(ctx context.Context, treeRoot string, files []*walk.File) ([]*walk.File, error) {
	if len(files) == 0 {
		return nil, nil
	}

	// os.MkdirTemp creates the directory with 0o700 permissions.
	dir, err := os.MkdirTemp("", "treelint-check-")
	if err != nil {
		return nil, fmt.Errorf("failed to create sandbox dir: %w", err)
	}

	defer func() { _ = os.RemoveAll(dir) }()

	for _, file := range files {
		if err := copyIntoSandbox(treeRoot, dir, file); err != nil {
			return nil, err
		}
	}

	maxBatch := len(files)
	if f.HasNoPositionalArgSupport() {
		maxBatch = 1
	}

	for start := 0; start < len(files); start += maxBatch {
		end := min(start+maxBatch, len(files))

		args := append([]string{}, f.config.Options...)
		for _, file := range files[start:end] {
			args = append(args, file.RelPath)
		}

		cmd := exec.CommandContext(ctx, f.executable, args...) //nolint:gosec
		cmd.Cancel = func() error { return cmd.Process.Signal(os.Interrupt) }
		cmd.Dir = dir

		if out, runErr := cmd.CombinedOutput(); runErr != nil {
			return nil, fmt.Errorf("formatter '%s' failed in sandbox: %w\n%s", f.name, runErr, out)
		}
	}

	var changed []*walk.File

	for _, file := range files {
		same, err := sameContent(file.Path, filepath.Join(dir, file.RelPath))
		if err != nil {
			return nil, err
		}

		if !same {
			changed = append(changed, file)
		}
	}

	return changed, nil
}

// copyIntoSandbox copies a file's content and permission bits into dir at its
// relative path. Symlinks are copied as their resolved regular-file contents; a
// link whose target resolves outside the tree root is a hard error (RFC 0001 §6
// and Security Considerations).
func copyIntoSandbox(treeRoot, dir string, file *walk.File) error {
	info, err := os.Lstat(file.Path)
	if err != nil {
		return fmt.Errorf("failed to lstat %s: %w", file.RelPath, err)
	}

	srcPath := file.Path

	if info.Mode()&os.ModeSymlink != 0 {
		resolved, err := filepath.EvalSymlinks(file.Path)
		if err != nil {
			return fmt.Errorf("failed to resolve symlink %s: %w", file.RelPath, err)
		}

		rel, err := filepath.Rel(treeRoot, resolved)
		if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(os.PathSeparator)) {
			return fmt.Errorf("symlink %s resolves outside the tree root", file.RelPath)
		}

		srcPath = resolved
	}

	content, err := os.ReadFile(srcPath)
	if err != nil {
		return fmt.Errorf("failed to read %s: %w", file.RelPath, err)
	}

	mode := os.FileMode(0o600)
	if fi, statErr := os.Stat(srcPath); statErr == nil {
		mode = fi.Mode().Perm()
	}

	dst := filepath.Join(dir, file.RelPath)
	if err := os.MkdirAll(filepath.Dir(dst), 0o700); err != nil {
		return fmt.Errorf("failed to create sandbox subdir: %w", err)
	}

	if err := os.WriteFile(dst, content, mode); err != nil {
		return fmt.Errorf("failed to write sandbox copy: %w", err)
	}

	return nil
}

func sameContent(a, b string) (bool, error) {
	ca, err := os.ReadFile(a)
	if err != nil {
		return false, fmt.Errorf("failed to read %s: %w", a, err)
	}

	cb, err := os.ReadFile(b)
	if err != nil {
		return false, fmt.Errorf("failed to read %s: %w", b, err)
	}

	return bytes.Equal(ca, cb), nil
}
