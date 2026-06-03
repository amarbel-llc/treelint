# Documentation

There is a `docs` package which can be built as follows:

```console
❯ nix build .#docs
```

This produces a static build of the docs and places it in a symlink called `result` in the same directory.

We can re-use this package as a [devshell], relying upon it to provide the necessary dependencies for developing the
docs.

```nix title="nix/devshells/docs.nix"
--8<-- "nix/packages/docs.nix"
```

The docs are based on [MkDocs] and the [MkDocs Material] theme.

## Serve locally

To serve the docs locally run `mkdocs serve` from the `docs` directory:

```console
❯ mkdocs serve
INFO    -  Building documentation...
INFO    -  Cleaning site directory
WARNING -  The following pages exist in the docs directory, but are not included in the "nav" configuration:
             - index.md
INFO    -  Documentation built in 0.26 seconds
INFO    -  [16:22:36] Watching paths for changes: 'docs/content', 'mkdocs.yml'
INFO    -  [16:22:36] Serving on http://127.0.0.1:8000/conformist/
```

## Versioning & Publication

Versioning of the docs is managed through [mike].

It is responsible for managing the structure of the `gh-pages` branch in the repository, which [Github Pages] is
configured to serve from.

!!! note

    More information about versioning with [MkDocs Material] and [mike] can be found [here](https://squidfunk.github.io/mkdocs-material/setup/setting-up-versioning/).

conformist does not currently publish this documentation site; build it locally
with the commands above to preview changes. treefmt's `gh-pages.yml` publishing
workflow was dropped during the migration to the eng conventions, so a conformist
docs-deployment workflow would need to be added if the site is ever published.

To preview the versions locally you can use `mike serve` instead of `mkdocs serve`.

!!! warning

    Be sure to have fetched the latest changes for the `gh-pages` branch first.
    This is especially important if you are using `mike` locally to make manual changes to the published site.

[Nix]: https://nixos.org
[Flake]: https://wiki.nixos.org/wiki/Flakes
[Nix derivation]: https://nix.dev/manual/nix/2.18/language/derivations
[Direnv]: https://direnv.net
[devshell]: https://nix.dev/tutorials/first-steps/declarative-shell.html
[MkDocs]: https://www.mkdocs.org/
[MkDocs Material]: https://squidfunk.github.io/mkdocs-material/
[Github Pages]: https://pages.github.com/
[mike]: https://github.com/jimporter/mike
