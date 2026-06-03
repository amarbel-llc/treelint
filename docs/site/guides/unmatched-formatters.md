# Handling Unmatched Files

By default, conformist lists all files that aren't matched by any formatter:

```console
$ conformist
WARN no formatter for path: .gitignore
WARN no formatter for path: LICENSE
WARN no formatter for path: README.md
WARN no formatter for path: go.mod
WARN no formatter for path: go.sum
WARN no formatter for path: build/build.go
# ...
```

This helps you decide whether to add formatters for specific files or ignore them entirely.

## Customizing Notifications

### Reducing Log Verbosity

If you find the unmatched file warnings too noisy, you can lower the logging level in your config:

`conformist.toml`:

```toml
on-unmatched = "debug"
```

To later find out what files are unmatched, you can override this setting via the command line:

```console
$ conformist --on-unmatched warn
```

### Enforcing Strict Matching

Another stricter policy approach is to fail the run if any unmatched files are found.
This can be paired with an `excludes` list to ignore specific files:

`conformist.toml`:

```toml
# Fail if any unmatched files are found
on-unmatched = "fatal"

# List files to explicitly ignore
excludes = [
  "LICENCE",
  "go.sum",
]
```
