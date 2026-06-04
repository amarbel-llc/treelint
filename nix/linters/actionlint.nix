# actionlint as a conformist LINTER (RFC 0001 §4). It statically checks GitHub
# Actions workflow files and exits non-zero on findings; it has no autofix, so
# it is check-only (a no-op in repair mode). Reclassified from a treefmt-nix
# "formatter" (conformist#6).
{ lib, mkLinterModule, ... }:
{
  meta.maintainers = [ "katexochen" ];
  meta.brokenPlatforms = lib.platforms.darwin;

  imports = [
    (mkLinterModule {
      name = "actionlint";
      includes = [
        ".github/workflows/*.yml"
        ".github/workflows/*.yaml"
        ".gitea/workflows/*.yml"
        ".gitea/workflows/*.yaml"
        ".forgejo/workflows/*.yml"
        ".forgejo/workflows/*.yaml"
      ];
    })
  ];
}
