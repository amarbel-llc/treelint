# dscanner as a conformist LINTER (RFC 0001 §4). `dscanner lint` statically
# analyses D source and exits non-zero on findings; check-only (a no-op in
# repair mode). Reclassified from a treefmt-nix "formatter" (conformist#6).
{ mkLinterModule, ... }:
{
  imports = [
    (mkLinterModule {
      name = "dscanner";
      args = [ "lint" ];
      includes = [
        "*.d"
      ];
    })
  ];
}
