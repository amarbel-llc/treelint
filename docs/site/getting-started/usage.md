---
outline: deep
---

# Usage

`conformist` has the following specification:

```console
--8<-- "docs/snippets/usage.txt"
```

Typically, you will execute `conformist` from the root of your repository with no arguments:

```console
❯ conformist
traversed 106 files
emitted 9 files for processing
formatted 6 files (2 changed) in 184ms
```

## Clear Cache

To force re-evaluation of the entire tree, you run `conformist` with the `-c` or `--clear-cache` flag:

```console
❯ conformist -c
traversed 106 files
emitted 106 files for processing
formatted 56 files (0 changed) in 363ms

❯ conformist --clear-cache
traversed 106 files
emitted 106 files for processing
formatted 56 files (0 changed) in 351ms
```

## Change working directory

Similar to [git](https://git-scm.com/), `conformist` has an option to [change working directory](./configure.md#working-dir)
before executing:

```console
❯ conformist -C test/examples --allow-missing-formatter
traversed 106 files
emitted 56 files for processing
formatted 46 files (1 changed) in 406ms
```

## Format files & directories

To format one or more specific files, you can pass them as arguments.

```console
> conformist default.nix walk/walk.go nix/devshells/renovate.nix
traversed 3 files
emitted 3 files for processing
formatted 3 files (0 changed) in 144ms
```

You can also pass directories:

```console
> conformist nix walk/cache
traversed 9 files
emitted 8 files for processing
formatted 7 files (0 changed) in 217ms
```

!!!note

    When passing directories as arguments, `conformist` will traverse them using the configured [walk](./configure.md#walk)
    strategy.

## Format stdin

Using the [stdin](./configure.md#stdin) option, `conformist` can format content passed via `stdin`, forwarding its
output to `stdout`:

```console
❯ cat default.nix | conformist --stdin foo.nix
# This file provides backward compatibility to nix < 2.4 clients
{system ? builtins.currentSystem}: let
  lock = builtins.fromJSON (builtins.readFile ./flake.lock);

  inherit
    (lock.nodes.flake-compat.locked)
    owner
    repo
    rev
    narHash
    ;

  flake-compat = fetchTarball {
    url = "https://github.com/${owner}/${repo}/archive/${rev}.tar.gz";
    sha256 = narHash;
  };

  flake = import flake-compat {
    inherit system;
    src = ./.;
  };
in
  flake.defaultNix
```

## Shell Completion

To generate completions for your preferred shell:

```console
❯ conformist --completion bash
❯ conformist --completion fish
❯ conformist --completion zsh
```

## CI integration

We recommend using the [CI option](./configure.md#ci) in continuous integration environments.

You can configure a `conformist` job in a GitHub pipeline for Ubuntu with `nix-shell` like this:

```yaml
name: conformist
on:
    pull_request:
    push:
        branches: main
jobs:
    formatter:
        runs-on: ubuntu-latest
        steps:
            - uses: actions/checkout@v4
            - uses: cachix/install-nix-action@v26
              with:
                  nix_path: nixpkgs=channel:nixos-unstable
            - uses: cachix/cachix-action@v14
              with:
                  name: nix-community
                  authToken: "${{ secrets.CACHIX_AUTH_TOKEN }}"
            - name: conformist
              run: nix-shell -p conformist --run "conformist --ci"
```
