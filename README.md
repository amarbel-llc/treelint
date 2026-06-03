<div align="center">

# conformist

**The linter and formatter multiplexer**

</div>

> **Status: early / pre-1.0.** conformist is a clean copy of
> [treefmt](https://github.com/numtide/treefmt) v2.5.0 that adds first-class
> _linting_ on top of treefmt's formatter multiplexing, per
> [RFC 0001](docs/rfcs/0001-linter-support-and-check-repair-modes.md). The
> `[linter.<name>]` config section, the `conformist check` subcommand, and
> repair-mode autofixes are implemented. Expect rough edges before 1.0.

## What it is

conformist runs all your formatters and linters with one command. It inherits
treefmt's model: conformist walks the tree, matches files to tools by glob, and
runs the matched tools in parallel, only on files that changed since the last
run.

The linter additions ([RFC 0001](docs/rfcs/0001-linter-support-and-check-repair-modes.md)):

- A `[linter.<name>]` config section parallel to `[formatter.<name>]`. Its
  `command` is a read-only check; an optional `repair-command` applies autofixes.
- First-class **repair** mode (the default — applies formatter and linter fixes)
  and **check** mode (read-only — reports without writing), exposed via a
  `conformist check` subcommand.
- A sandbox-copy-and-diff strategy so fix-only formatters can be checked without
  ever writing to your source tree (so checks work even on a read-only tree).

## Install

With Nix (the supported path):

```
nix build github:amarbel-llc/conformist
./result/bin/conformist --help
```

Or from source with Go ≥ 1.26:

```
go build -o conformist .
```

## Usage

Generate a starter config (writes `conformist.toml`):

```
conformist --init
```

Format the tree (repair mode):

```
conformist
```

Check the tree read-only — runs every formatter and linter without writing.
Exits 0 when clean, 1 when findings are detected, 2 on an operational error:

```
conformist check
```

Print version:

```
conformist version
```

## Configuration

Formatters are specified in `conformist.toml` (or `.conformist.toml`), discovered by
searching upward from the working directory:

```toml
[formatter.nix]
command = "nixfmt"
includes = ["*.nix"]

[formatter.rust]
command = "rustfmt"
options = ["--edition", "2018"]
includes = ["*.rs"]
```

A formatter may declare a native read-only check via `check-command` /
`check-options` for use by `conformist check`; without one, the formatter is
checked through a sandbox copy. Set `sandbox = true` to force sandbox checking
even when a check command exists.

Linters use a parallel `[linter.<name>]` section. Its `command` is the
read-only check (it must exit non-zero on findings); add `repair-command` /
`repair-options` to apply autofixes in repair mode. A linter with no
`repair-command` is a no-op in repair mode:

```toml
[linter.shellcheck]
command = "shellcheck"
includes = ["*.sh"]

[linter.ruff]
command = "ruff"
options = ["check"]
repair-command = "ruff"
repair-options = ["check", "--fix"]
includes = ["*.py"]
```

## Formatter specification

conformist runs tools that follow the
[formatter specification](docs/site/reference/formatter-spec.md): files are
passed as arguments, the tool writes back only on change, and it exits non-zero
on error.

## Provenance & license

conformist is derived from [numtide/treefmt](https://github.com/numtide/treefmt)
v2.5.0 and is an independent project (not a GitHub fork). treefmt's original
copyright and MIT license are retained in [LICENSE](LICENSE); see
[NOTICE](NOTICE) for provenance. conformist is released under the MIT license.
