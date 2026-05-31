---
status: proposed
date: 2026-05-30
---

# Linter Support: the `[linter.<name>]` Config Section, the `check` Subcommand, and Check/Repair Execution Modes

## Abstract

This document specifies how treelint runs linters alongside formatters. It
defines a new `[linter.<name>]` TOML configuration section parallel to the
existing `[formatter.<name>]` section, two execution modes (**repair**, which
writes fixes to the working tree, and **check**, which is strictly read-only),
and a `treelint check` subcommand that verifies a tree without modifying it.
Check mode for tools that only know how to rewrite files in place is realized
by copying matched files into a private sandbox, running the tool there, and
diffing the result — so source files are never written during a check, even on
a read-only tree.

## Introduction

treelint is a clean copy of treefmt v2.5.0 (the formatter multiplexer). treefmt
supports only *formatters*: tools invoked as `<command> [options] [...files]`
that rewrite files in place. It has no first-class concept of a *linter* (a tool
that inspects files and reports problems without necessarily rewriting them) and
no read-only verification mode.

treefmt's check-like behavior (`--ci` / `--fail-on-change`) is implemented
indirectly: it runs formatters, which write to disk, then infers "this file
needed formatting" from a change in the file's modification time and size. This
depends on formatter-spec rule 2 ("If there are no changes to the original file,
the formatter MUST NOT write to the original location") and has two consequences
this specification removes:

1. A check cannot run on a read-only source tree, because the formatter attempts
   to write (see informative reference [treefmt#500]).
2. There is no clean place for tools whose only job is to *report* (linters) —
   they neither fit the "writes back fixes" model nor have their non-zero exit
   code surfaced as a first-class result (see informative reference
   [treefmt#11]).

This specification defines the configuration interface, the CLI contract, and
the execution semantics needed for treelint to run linters and to verify a tree
without mutating it. It does not specify result caching, which is left to a
future revision.

## Requirements Language

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD",
"SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be
interpreted as described in RFC 2119.

## Specification

### 1. Terminology

- **Tool** — an external executable invoked by treelint, configured under either
  `[formatter.<name>]` or `[linter.<name>]`.
- **Formatter** — a tool whose primary action rewrites files in place to
  normalize their formatting. Configured under `[formatter.<name>]`.
- **Linter** — a tool whose primary action inspects files and reports problems,
  exiting non-zero when problems are found. Configured under `[linter.<name>]`.
- **Repair action** — an invocation of a tool that is permitted to write to the
  working tree (a formatter's rewrite, or a linter's autofix).
- **Check action** — an invocation, or synthesized evaluation, of a tool that
  MUST NOT write to the working tree and that yields a binary outcome per file:
  *clean* or *finding*.
- **Finding** — a single check result indicating that a file is not conformant:
  either a formatter would change the file, or a linter reported a problem in it.
- **Sandbox** — a private temporary directory into which matched files are copied
  so that a repair action can be run without touching the working tree.

### 2. Execution Modes

treelint operates in exactly one of two modes per invocation.

- In **repair mode**, treelint runs each matched tool's repair action. Repair
  mode MAY write to the working tree.
- In **check mode**, treelint runs each matched tool's check action. Check mode
  MUST NOT write to any file inside the configured tree root.

The default invocation (`treelint [paths...]`) runs in repair mode. The
`treelint check [paths...]` subcommand (Section 5) runs in check mode.

The section a tool is configured under determines which action its `command`
field denotes:

- For a `[formatter.<name>]`, `command` is the **repair** action.
- For a `[linter.<name>]`, `command` is the **check** action.

The action for the opposite mode is supplied by a companion field (Sections 3
and 4) or, for formatters in check mode, synthesized via the sandbox strategy
(Section 6).

### 3. The `[formatter.<name>]` Section

The existing formatter schema is retained. Each `<name>` MUST match the regular
expression `^[a-zA-Z0-9_-]+$`.

| Field | Type | Required | Meaning |
|-------|------|----------|---------|
| `command` | string | MUST | Repair action executable. Invoked as `command [options] [...files]`. |
| `options` | array of string | MAY | Arguments inserted before the file list. |
| `includes` | array of string | MUST (≥1) | Glob patterns selecting files this formatter processes. |
| `excludes` | array of string | MAY | Glob patterns removing files from this formatter. |
| `priority` | integer | MAY | Execution order within a file's tool sequence; lower runs first. Default `0`. |
| `no-positional-arg-support` | boolean | MAY | If `true`, the tool MUST be invoked with at most one file at a time. |
| `check-command` | string | MAY | A native read-only check action. See below. |
| `check-options` | array of string | MAY | Arguments for `check-command`. |
| `sandbox` | boolean | MAY | If `true`, force sandbox execution (Section 6) even when a native check action exists. Default `false`. |

A formatter's `command` (repair action) MUST conform to the treelint formatter
specification (files passed as arguments; writes back only on change; non-zero
exit on error).

In check mode, treelint determines a formatter's check action as follows:

1. If `sandbox` is `true`, the formatter is checked via the sandbox strategy
   (Section 6).
2. Otherwise, if `check-command` is set, treelint MUST run
   `check-command [check-options] [...files]` directly against the working-tree
   files. That command MUST NOT write to the files and MUST exit non-zero if and
   only if at least one of the passed files is not conformant.
3. Otherwise, treelint MUST check the formatter via the sandbox strategy
   (Section 6) using its repair `command`/`options`.

### 4. The `[linter.<name>]` Section

`[linter.<name>]` is a new top-level table, parallel to `[formatter.<name>]`.
Each `<name>` MUST match `^[a-zA-Z0-9_-]+$`. A linter name MAY collide with a
formatter name; the two are independent tools.

| Field | Type | Required | Meaning |
|-------|------|----------|---------|
| `command` | string | MUST | Check action executable. Invoked as `command [options] [...files]`. Read-only; non-zero exit signals findings. |
| `options` | array of string | MAY | Arguments inserted before the file list. |
| `includes` | array of string | MUST (≥1) | Glob patterns selecting files this linter inspects. |
| `excludes` | array of string | MAY | Glob patterns removing files from this linter. |
| `priority` | integer | MAY | Execution order within a file's tool sequence; lower runs first. Default `0`. |
| `no-positional-arg-support` | boolean | MAY | If `true`, the tool MUST be invoked with at most one file at a time. |
| `repair-command` | string | MAY | An autofix action used in repair mode. See below. |
| `repair-options` | array of string | MAY | Arguments for `repair-command`. |

A linter's `command` (check action) MUST be read-only: it MUST NOT write to any
file it is passed. It MUST exit `0` when all passed files are clean and MUST exit
non-zero when at least one passed file has a finding. It SHOULD print diagnostics
to stderr.

In repair mode, treelint determines a linter's repair action as follows:

1. If `repair-command` is set, treelint MUST run
   `repair-command [repair-options] [...files]` against the working-tree files.
   This action MAY write to those files.
2. Otherwise, the linter has no repair action and treelint MUST treat it as a
   no-op in repair mode (the linter is not run; no finding is reported).

In check mode, treelint MUST run a linter's `command [options] [...files]`
against the working-tree files (no sandbox is used unless `sandbox` semantics are
later extended to linters).

### 5. The `check` Subcommand

treelint MUST provide a `check` subcommand:

```
treelint check [flags] [paths...]
```

The subcommand MUST honor the same configuration discovery, tree-root
resolution, walking, and include/exclude matching as the default (repair)
invocation. It runs in check mode (Section 2). It MUST NOT modify any file
inside the tree root.

For every file selected by the walk:

- Each matched formatter is evaluated via its check action (Section 3).
- Each matched linter is evaluated via its check action (Section 4).

When a path is matched by multiple tools, all matched tools MUST be evaluated.
Tools are ordered by ascending `priority`.

The subcommand MUST report, to stdout, the set of files with findings together
with the tool that produced each finding. Per-tool diagnostic output SHOULD be
forwarded to stderr. The exit code is defined in Section 7.

Flag requirements:

- `treelint check` MUST accept the file/path selection flags accepted by the
  default invocation (e.g. `--tree-root`, `--walk`, `--excludes`,
  `--config-file`).
- `treelint check` MAY accept `--formatters` and a `--linters` flag to restrict
  the evaluated tool sets. When neither is given, all configured tools of both
  kinds are eligible.
- `treelint check` MUST NOT honor flags whose only effect is to write to the
  tree (e.g. it MUST ignore or reject `--fail-on-change`, whose semantics are
  subsumed by the check exit code).

### 6. Sandbox-and-Diff Strategy

This strategy synthesizes a check action for a fix-only formatter (Section 3,
case 3, and the `sandbox = true` case). For a given formatter and its set of
matched files `F = {f1, …, fn}`:

1. treelint MUST create a private temporary directory `D` with permissions that
   deny access to other users (mode `0700`).
2. For each `fi`, treelint MUST copy the file's contents and mode bits into `D`,
   preserving `fi`'s path relative to the tree root. Symbolic links MUST be
   copied as their resolved regular-file contents; treelint MUST NOT copy or
   follow a link whose target resolves outside the tree root, and MUST treat such
   a file as a hard error (Section 7, error class).
3. treelint MUST run the formatter's repair `command [options]` with the copied
   paths in `D` as the file arguments, with the working directory set to `D`.
4. For each `fi`, treelint MUST compare the post-run copy in `D` against the
   original `fi` by content. If they differ, `fi` is a finding for this
   formatter. Comparison MUST be by content (e.g. byte length and a content
   hash), not by modification time.
5. treelint MUST remove `D` and its contents before the invocation exits,
   including on error.
6. At no point MUST this strategy write to, rename, or delete any path outside
   `D`.

A formatter checked via this strategy still MUST conform to the formatter
specification; a formatter that writes outside its file arguments, or that
writes when no change is needed, MAY produce spurious findings.

### 7. Exit Codes

The `treelint check` subcommand MUST use the following exit codes:

| Code | Condition |
|------|-----------|
| `0` | Every evaluated file is clean: no formatter would change a file and no linter reported a finding. |
| `1` | At least one finding was produced and no error class condition occurred. |
| `2` | An error class condition occurred: a configured tool's executable was not found, the configuration was invalid, a sandbox operation failed, or a tool exited in a way that indicates operational failure rather than a finding. |

When both findings (`1`) and an error class condition (`2`) occur, treelint MUST
exit `2`.

A linter's non-zero exit is interpreted as *findings* (`1`), not an error, unless
treelint can distinguish an operational failure (for example, the executable is
missing, which is `2`). Implementations SHOULD document any tool-specific exit
code interpretation they add.

### 8. Examples

Valid configuration combining formatters and linters:

```toml
# Fix-only formatter: no native check, so `treelint check` sandboxes + diffs it.
[formatter.gofmt]
command = "gofmt"
options = ["-w"]
includes = ["*.go"]

# Formatter with a native read-only check used directly by `treelint check`.
[formatter.prettier]
command = "prettier"
options = ["--write"]
check-command = "prettier"
check-options = ["--check"]
includes = ["*.js", "*.ts", "*.css", "*.md"]

# Check-only linter: read-only, no autofix. No-op in repair mode.
[linter.shellcheck]
command = "shellcheck"
includes = ["*.sh"]

# Linter with an autofix used in repair mode.
[linter.ruff]
command = "ruff"
options = ["check"]
repair-command = "ruff"
repair-options = ["check", "--fix"]
includes = ["*.py", "*.pyi"]
```

Invocations:

```
# Repair mode (default): gofmt -w, prettier --write, ruff check --fix.
# shellcheck does not run (no repair action).
treelint

# Check mode: read-only. gofmt is sandboxed and diffed; prettier --check,
# shellcheck, and ruff check run against the working tree. Exits 1 if any
# file needs formatting or any linter reports a problem; 0 if clean.
treelint check

# Check only Go and shell, restricted by tool name.
treelint check --formatters gofmt --linters shellcheck
```

Invalid configuration (rejected at load, exit `2`):

```toml
[linter.bad name]          # name does not match ^[a-zA-Z0-9_-]+$
command = "foo"
includes = ["*.x"]

[linter.no_includes]       # missing required includes
command = "foo"

[linter.no_command]        # missing required command
includes = ["*.x"]
```

## Security Considerations

- **Arbitrary command execution.** Both `[formatter.<name>]` and
  `[linter.<name>]` name executables that treelint runs with the invoking user's
  privileges. A treelint configuration file is therefore as trust-sensitive as a
  shell script. Implementations MUST resolve executables via `PATH` lookup at the
  tree root and SHOULD make the resolved executable path visible in verbose logs.
  Consumers MUST NOT run treelint against a configuration from an untrusted
  source without review.
- **Sandbox isolation.** The sandbox directory MUST be created with mode `0700`
  to prevent other local users from reading copied source or injecting files
  that the formatter would process. Implementations SHOULD create the sandbox
  under a per-invocation, unpredictable path.
- **Path traversal via includes/symlinks.** File selection and sandbox copying
  MUST be confined to the tree root. A symlink whose target resolves outside the
  tree root MUST NOT be copied or followed (Section 6, step 2); treating it as an
  error prevents a malicious or misconfigured tree from causing reads or writes
  outside the intended scope.
- **Temp-file cleanup and information disclosure.** Copied source resides in the
  sandbox for the duration of a check. Implementations MUST remove the sandbox on
  exit, including on error and signal-driven termination where feasible, so that
  source contents are not left readable after the process ends.
- **Check-mode write invariant.** The guarantee that check mode never writes to
  the tree depends on (a) linter `command`s being read-only by contract and
  (b) fix-only formatters being run only inside the sandbox. A tool that violates
  its declared contract can break this invariant; the `sandbox = true` option
  exists so operators can force isolation for tools they do not fully trust.

## Conformance Testing

Conformance tests for this specification live in
`docs/rfcs/../../zz-tests_bats/` (the treelint repository's `zz-tests_bats/`
directory).

Tests use binary injection via `bats-emo`:

    require_bin TREELINT treelint

This keeps the suite portable across implementations of this specification (for
example, a future rewrite can run the same tests by injecting its own binary).

### Covered Requirements

| Requirement | Test File | Description |
|-------------|-----------|-------------|
| Section 2, check mode MUST NOT write | `test_check_readonly.bats` | Run `treelint check` against a tree whose files are made read-only; assert exit reflects findings and no source file is modified. |
| Section 3, fix-only formatter check | `test_check_sandbox.bats` | A `gofmt -w` formatter with no `check-command`; assert a misformatted file yields a finding and is left byte-identical. |
| Section 3, native `check-command` | `test_check_native.bats` | A formatter with `check-command`; assert the check command (not the repair command) is invoked and the source is untouched. |
| Section 4, `[linter.<name>]` schema | `test_linter_config.bats` | Valid linter config loads; invalid name / missing command / missing includes each exit `2`. |
| Section 4, linter findings | `test_linter_findings.bats` | A linter that exits non-zero on a bad file produces a finding; a clean file does not. |
| Section 4, linter autofix in repair mode | `test_linter_repair.bats` | A linter with `repair-command` rewrites a file in repair mode; a check-only linter is a no-op in repair mode. |
| Section 5, `check` subcommand selection | `test_check_cli.bats` | `--formatters` / `--linters` restrict evaluated tools; default evaluates both kinds. |
| Section 7, exit codes | `test_check_exit_codes.bats` | Clean tree exits `0`; findings exit `1`; missing executable exits `2`; findings + error exits `2`. |

## Compatibility

- **Existing configurations remain valid.** `[linter.<name>]` and the new
  formatter keys (`check-command`, `check-options`, `sandbox`) are additive and
  OPTIONAL. A configuration that uses none of them behaves exactly as it does in
  treefmt v2.5.0, except that check mode for a fix-only formatter is now realized
  via the sandbox strategy rather than via in-place writing plus mtime
  inference.
- **Upstream treefmt ignores the new section.** treefmt has no `linter`
  configuration field, so an unknown `[linter.*]` table is silently ignored by
  older binaries. Operators who share a configuration across both tools SHOULD
  be aware that linters will simply not run under treefmt.
- **Config discovery names.** This document specifies the `treelint` command and
  the `[linter.<name>]` / `[formatter.<name>]` tables. The config file names
  (`treefmt.toml` / `.treefmt.toml`), the `TREEFMT_`-prefixed environment
  variables, and the `treelint`-vs-`treefmt` binary name are governed by a
  separate user-facing rename and are out of scope here; until that rename lands,
  the treefmt-era names apply.
- **Versioning.** Backwards-incompatible changes to the `[linter.<name>]` schema
  or the `check` exit codes MUST be introduced under a superseding RFC.

## References

### Normative

- [RFC 2119] Bradner, S., "Key words for use in RFCs to Indicate Requirement
  Levels", BCP 14, RFC 2119, March 1997.
- [treelint formatter specification] `docs/site/reference/formatter-spec.md` —
  the rules a formatter's repair action MUST satisfy (files-as-arguments,
  write-only-on-change, non-zero-on-error).

### Informative

- [treefmt#11] numtide/treefmt issue #11, "Add support for linters",
  https://github.com/numtide/treefmt/issues/11 — the upstream design discussion
  motivating a `[linter.<name>]` section and check/repair modes.
- [treefmt#500] numtide/treefmt issue #500, "A `--check` flag that won't actually
  apply the formatting", https://github.com/numtide/treefmt/issues/500 — the
  read-only-check use case this specification's check mode addresses.
