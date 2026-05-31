# Configure

`treelint`'s behaviour can be influenced in one of three ways:

1. Process flags and arguments
2. Environment variables
3. A [TOML] based config file

There is an order of precedence between these mechanisms as listed above, with process flags having the highest
precedence and values in the configuration file having the lowest.

!!!note

    Some options can **only be configured as process flags**,
    others may support **process flags and environment variables**,
    and others still may support **all three mechanisms**.

## Config File

The `treelint` configuration file is a mixture of global options and formatter sections.

It should be named `treelint.toml` or `.treelint.toml`, and typically resides at the root of a repository.

When executing `treelint` within a subdirectory, `treelint` will search upwards in the directory structure, looking for
`treelint.toml` or `.treelint.toml`.
You can change this behaviour using the [config-file](#config-file_1) options

!!! tip

    When starting a new project you can generate an initial config file using `treelint --init`

```nix title="treelint.toml"
--8<-- "cmd/init/init.toml"
```

## Global Options

### `allow-missing-formatter`

Do not exit with error if a configured formatter is missing.

=== "Flag"

    ```console
    treelint --allow-missing-formatter true
    ```

=== "Env"

    ```console
    TREELINT_ALLOW_MISSING_FORMATTER=true treelint
    ```

=== "Config"

    ```toml
    allow-missing-formatter = true
    ```

### `ci`

Runs treelint in a CI mode, enabling [no-cache](#no-cache), [fail-on-change](#fail-on-change) and adjusting some other settings best suited to a
continuous integration environment.

=== "Flag"

    ```console
    treelint --ci
    ```

=== "Env"

    ```console
    TREELINT_CI=true treelint
    ```

### `clear-cache`

Reset the evaluation cache. Use in case the cache is not precise enough.

=== "Flag"

    ```console
    treelint -c
    treelint --clear-cache
    ```

=== "Env"

    ```console
    TREELINT_CLEAR_CACHE=true treelint
    ```

### `config-file`

=== "Flag"

    ```console
    treelint --config-file /tmp/treelint.toml
    ```

=== "Env"

    ```console
    TREELINT_CONFIG=/tmp/treelint.toml treelint
    ```

### `cpu-profile`

The file into which a [pprof](https://github.com/google/pprof) cpu profile will be written.

=== "Flag"

    ```console
    treelint --cpu-profile ./cpu.pprof
    ```

=== "Env"

    ```console
    TREELINT_CPU_PROFILE=./cpu.pprof treelint
    ```

=== "Config"

    ```toml
    cpu-profile = "./cpu.pprof"
    ```

### `excludes`

An optional list of [glob patterns](#glob-patterns-format) used to exclude files from all formatters.

=== "Flag"

    ```console
    treelint --excludes *.toml,*.php,README
    ```

=== "Env"

    ```console
    TREELINT_EXCLUDES="*.toml,*.php,README" treelint
    ```

=== "Config"

    ```toml
    excludes = ["*.toml", "*.php", "README"]
    ```

### `fail-on-change`

Exit with error if any changes were made during execution.

=== "Flag"

    ```console
    treelint --fail-on-change true
    ```

=== "Env"

    ```console
    TREELINT_FAIL_ON_CHANGE=true treelint
    ```

=== "Config"

    ```toml
    fail-on-change = true
    ```

### `formatters`

A list of formatters to apply.
Defaults to all configured formatters.

=== "Flag"

    ```console
    treelint -f go,toml,haskell
    treelint --formatters go,toml,haskell
    ```

=== "Env"

    ```console
    TREELINT_FORMATTERS=go,toml,haskell treelint
    ```

=== "Config"

    ```toml
    formatters = ["go", "toml", "haskell"]

    [formatter.go]
    ...

    [formatter.toml]
    ...

    [formatter.haskell]
    ...

    [formatter.ruby]
    ...

    [formatter.shellcheck]
    ...
    ```

### `no-cache`

Ignore the evaluation cache entirely. Useful for CI.

=== "Flag"

    ```console
    treelint --no-cache
    ```

=== "Env"

    ```console
    TREELINT_NO_CACHE=true treelint
    ```

### `on-unmatched`

Log paths that did not match any formatters at the specified log level.
Possible values are `<debug|info|warn|error|fatal>`.

!!! warning

    If you select `fatal`, the process will exit immediately with a non-zero exit.

=== "Flag"

    ```console
    treelint -u debug
    treelint --on-unmatched debug
    ```

=== "Env"

    ```console
    TREELINT_ON_UNMACTHED=info treelint
    ```

=== "Config"

    ```toml
    on-unmatched = "debug"
    ```

### `quiet`

Suppress all output except for errors.

=== "Flag"

    ```console
    treelint --quiet
    ```

=== "Env"

    ```console
    TREELINT_QUIET=true treelint
    ```

### `stdin`

Format the context passed in via stdin.

!!! note
You must provide a single path argument, the value of which is used to match against the configured formatters.

=== "Flag"

    ```console
    cat ../test.go | treelint --stdin foo.go
    ```

### `tree-root`

The root directory from which treelint will start walking the filesystem.
Defaults to the directory containing the config file.

=== "Flag"

    ```console
    treelint --tree-root /tmp/foo
    ```

=== "Env"

    ```console
    TREELINT_TREE_ROOT=/tmp/foo treelint
    ```

=== "Config"

    ```toml
    tree-root = "/tmp/foo"
    ```

### `tree-root-cmd`

Command to run to find the tree root.
It is parsed using [shlex](https://github.com/google/shlex/tree/master), to allow quoting arguments that contain whitespace.
If you wish to pass arguments containing quotes, you should use nested quotes e.g. `"'"` or `'"'`.

!!!note

    If [walk](#walk) is set to `git` and no tree root option has been defined, `tree-root-cmd` will be defaulted to
    `git rev-parse --show-toplevel`.

    If [walk](#walk) is set to `jujutsu` and no tree root option has been defined, `tree-root-cmd` will be defaulted to
    `jj workspace root`.

    if [walk](#walk) is set to `auto` (the default), `treelint` will check if the [working directory](#working-dir) is
    inside a git worktree. If it is, `tree-root-cmd` will be defaulted as described above for `git`. If the [working
    directory](#working-dir) is inside a jujutsu worktree the `tree-root-cmd` will be defaulted as described above for
    `jujutsu`.

=== "Flag"

    ```console
    treelint --tree-root-cmd "git rev-parse --show-toplevel"
    ```

=== "Env"

    ```console
    TREELINT_TREE_ROOT_CMD="git rev-parse --show-toplevel" treelint
    ```

=== "Config"

    ```toml
    tree-root-cmd = "git rev-parse --show-toplevel"
    ```

### `tree-root-file`

File to search for to find the tree root (if `tree-root` is not set)

=== "Flag"

    ```console
    treelint --tree-root-file .git/config
    ```

=== "Env"

    ```console
    TREELINT_TREE_ROOT_FILE=.git/config treelint
    ```

=== "Config"

    ```toml
    tree-root-file = ".git/config"
    ```

### `verbose`

Set the verbosity level of logs:

- `0` => `warn`
- `1` => `info`
- `2` => `debug`

=== "Flag"

    The number of `v`'s passed matches the level set.

    ```console
    treelint -vv
    ```

=== "Env"

    ```console
    TREELINT_VERBOSE=1 treelint
    ```

=== "Config"

    ```toml
    verbose = 2
    ```

### `walk`

The method used to traverse the files within the tree root.
Currently, we support 'auto', 'git', 'jujutsu' or 'filesystem'

=== "Flag"

    ```console
    treelint --walk filesystem
    ```

=== "Env"

    ```console
    TREELINT_WALK=filesystem treelint
    ```

=== "Config"

    ```toml
    walk = "filesystem"
    ```

### `working-dir`

Run as if `treelint` was started in the specified working directory instead of the current working directory.

=== "Flag"

    ```console
    treelint -C /tmp/foo
    treelint --working-dir /tmp/foo
    ```

=== "Env"

    ```console
    TREELINT_WORKING_DIR=/tmp/foo treelint
    ```

## Formatter Options

Formatters are configured using a [table](https://toml.io/en/v1.0.0#table) entry in `treelint.toml` of the form
`[formatter.<name>]`:

```toml
[formatter.alejandra]
command = "alejandra"
includes = ["*.nix"]
excludes = ["examples/nix/sources.nix"]
priority = 1

[formatter.deadnix]
command = "deadnix"
options = ["-e"]
includes = ["*.nix"]
priority = 2
```

### `command`

The command to invoke when applying the formatter.

### `options`

An optional list of args to be passed to `command`.

### `includes`

A list of [glob patterns](#glob-patterns-format) used to determine whether the formatter should be applied against a given path.

### `excludes`

An optional list of [glob patterns](#glob-patterns-format) used to exclude certain files from this formatter.

### `priority`

Influences the order of execution. Greater precedence is given to lower numbers, with the default being `0`.

### `no-positional-arg-support`

If `true`, `treelint` will invoke the formatter with no more than 1 file at a time.

Enable this if the formatter can only format 1 file at a time (a violation of
[rule 1 of the formatter spec](https://treefmt.com/latest/reference/formatter-spec/#1-files-passed-as-arguments)).

## Same file, multiple formatters?

For each file, `treelint` determines a list of formatters based on the configured `includes` / `excludes` rules. This list is
then sorted, first by priority (lower the value, higher the precedence) and secondly by formatter name (lexicographically).

The resultant sequence of formatters is used to create a batch key, and similarly matched files get added to that batch
until it is full, at which point the files are passed to each formatter in turn.

This means that `treelint` **guarantees only one formatter will be operating on a given file at any point in time**.
Another consequence is that formatting is deterministic for a given file and a given `treelint` configuration.

By setting the priority fields appropriately, you can control the order in which those formatters are applied for any
files they _both happen to match on_.

## Glob patterns format

This is a variant of the Unix glob pattern. It supports all the usual
selectors such as `*` and `?`.

### Examples

- `*.go` - match all files in the project that end with a ".go" file extension.
- `vendor/*` - match all files under the vendor folder, recursively.

## Supported Formatters

Any formatter that follows the [spec] is supported out of the box.

Already 60+ formatters are supported.

To find examples, take a look at <https://github.com/numtide/treefmt-nix/tree/main/examples>.

If you are a Nix user, you might also like <https://github.com/numtide/treefmt-nix>, which uses Nix to pull in the right formatter package and seamlessly integrates both together.

[spec]: ../reference/formatter-spec.md
[TOML]: https://toml.io
