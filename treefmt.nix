# `nix fmt` configuration (treefmt-nix). Drives `just codemod-fmt` (write mode)
# and `just lint-fmt` / `nix build .#checks.<sys>.formatting` (read-only gate).
{ ... }:
{
  projectRootFile = "flake.nix";

  programs.gofmt.enable = true;
  programs.nixfmt.enable = true;
  programs.taplo.enable = true;

  settings.global.excludes = [
    # Generated / locked — not hand-formatted.
    "gomod2nix.toml"
    "flake.lock"
    "go.sum"
    # treefmt's test corpus contains files deliberately mis-formatted as
    # formatter-test fixtures; formatting them would corrupt the suite.
    "test/**"
    # Prose and design docs are out of scope for code formatters.
    "docs/**"
    "*.md"
    "LICENSE"
    "NOTICE"
  ];
}
