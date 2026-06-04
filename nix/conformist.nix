# conformist's own config, consumed by self.lib.evalModule (see flake.nix).
# This replaces the former treefmt.nix: conformist now self-consumes its own Nix
# module instead of treefmt-nix (issue #4). Drives `nix fmt` (write mode via
# build.wrapper) and `nix build .#checks.<sys>.formatting` (read-only
# `conformist check` via build.check). `package` is injected by flake.nix.
{ ... }:
{
  projectRootFile = "flake.nix";

  # Formatters.
  programs.gofmt.enable = true;
  programs.nixfmt.enable = true;
  programs.taplo.enable = true;

  # Linter (RFC 0001 §4): shellcheck inspects the shell in the justfile recipes
  # and any *.sh / *.bash / *.envrc in the tree, and dogfoods the [linter.*]
  # path end-to-end.
  linters.shellcheck.enable = true;

  # Whole-tree check (passes-files=false): conformist self-enforces eng-versioning(7)
  # — version.env must declare `export CONFORMIST_VERSION=<semver>`. Reads only
  # committed files, so it runs in the sandboxed checks.formatting gate.
  linters.eng-versioning.enable = true;

  # Prefer top-level `excludes` over the deprecated `global.excludes`. These
  # apply to formatters and linters alike, so the test/** fixtures (deliberately
  # mis-formatted) are not linted or format-checked.
  settings.excludes = [
    # Generated / locked — not hand-formatted.
    "gomod2nix.toml"
    "flake.lock"
    "go.sum"
    # conformist's test corpus contains files deliberately mis-formatted as
    # formatter-test fixtures; formatting them would corrupt the suite.
    "test/**"
    # Prose and design docs are out of scope for code formatters.
    "docs/**"
    "*.md"
    "LICENSE"
    "NOTICE"
  ];
}
