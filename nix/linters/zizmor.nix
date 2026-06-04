# zizmor as a conformist LINTER (RFC 0001 §4). It audits GitHub Actions
# workflows for security issues and exits non-zero on findings; no autofix, so
# check-only (a no-op in repair mode). Reclassified from a treefmt-nix
# "formatter" (conformist#6).
{ lib, mkLinterModule, ... }:
{
  meta.maintainers = [
    "NixOS/nixpkgs-ci"
    "katexochen"
  ];
  meta.brokenPlatforms = lib.platforms.darwin;

  imports = [
    (mkLinterModule {
      name = "zizmor";
      includes = [
        ".github/workflows/*.yml"
        ".github/workflows/*.yaml"
        ".github/actions/**/*.yml"
        ".github/actions/**/*.yaml"
      ];
    })
  ];
}
