# hlint as a conformist LINTER (RFC 0001 §4). It reports Haskell lint
# suggestions and exits non-zero on findings. hlint can apply refactors via
# apply-refact (`--refactor`), but that needs an extra tool and is not wired
# here, so it is check-only for now (a no-op in repair mode). Reclassified from
# a treefmt-nix "formatter" (conformist#6). The `-j` arg runs checks in
# parallel.
{ mkLinterModule, ... }:
{
  meta.maintainers = [ ];

  imports = [
    (mkLinterModule {
      name = "hlint";
      args = [ "-j" ];
      includes = [ "*.hs" ];
    })
  ];
}
