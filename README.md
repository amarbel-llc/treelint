<div align="center">

# treelint

**The linter and formatter multiplexer**

</div>

> **Status: early / pre-1.0.** treelint is a clean copy of
> [treefmt](https://github.com/numtide/treefmt) v2.5.0 that adds first-class
> _linting_ on top of treefmt's formatter multiplexing. The linter feature is
> currently **designed but not yet implemented** — see
> [RFC 0001](docs/rfcs/0001-linter-support-and-check-repair-modes.md). Today
> treelint behaves as treefmt does (formatter multiplexing); the
> `[linter.<name>]` config section and `treelint check` subcommand described
> below are the in-progress design.

## What it is

treelint runs all your formatters — and, by design, your linters — with one
command. It inherits treefmt's model: treelint walks the tree, matches files to
tools by glob, and runs the matched tools in parallel, only on files that
changed since the last run.

The linter additions ([RFC 0001](docs/rfcs/0001-linter-support-and-check-repair-modes.md)):

- A `[linter.<name>]` config section parallel to `[formatter.<name>]`.
- First-class **repair** mode (the default — applies fixes) and **check** mode
  (read-only — reports without writing), exposed via a `treelint check`
  subcommand.
- A sandbox-copy-and-diff strategy so fix-only formatters can be checked without
  ever writing to your source tree (so checks work even on a read-only tree).

## Install

With Nix (the supported path):

```
nix build github:amarbel-llc/treelint
./result/bin/treelint --help
```

Or from source with Go ≥ 1.26:

```
go build -o treelint .
```

## Usage

Generate a starter config (writes `treelint.toml`):

```
treelint --init
```

Format the tree (repair mode):

```
treelint
```

Check the tree read-only (planned — see RFC 0001):

```
treelint check
```

Print version:

```
treelint version
```

## Configuration

Formatters are specified in `treelint.toml` (or `.treelint.toml`), discovered by
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

Linters will use a parallel `[linter.<name>]` section
([RFC 0001](docs/rfcs/0001-linter-support-and-check-repair-modes.md)):

```toml
[linter.shellcheck]
command = "shellcheck"
includes = ["*.sh"]
```

## Formatter specification

treelint runs tools that follow the
[formatter specification](docs/site/reference/formatter-spec.md): files are
passed as arguments, the tool writes back only on change, and it exits non-zero
on error.

## Provenance & license

treelint is derived from [numtide/treefmt](https://github.com/numtide/treefmt)
v2.5.0 and is an independent project (not a GitHub fork). treefmt's original
copyright and MIT license are retained in [LICENSE](LICENSE); see
[NOTICE](NOTICE) for provenance. treelint is released under the MIT license.
