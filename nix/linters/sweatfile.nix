# eng convention: a leaf repo's spinclass sweatfile pre-merge hook should be just
# `just` — the default recipe is the CI-equivalent lane (eng-design_patterns-justfile(7)
# DEFAULT RECIPE), so the gate runs `just`, not a hand-listed set of recipes.
# Whole-tree check (passes-files=false): reads the sweatfile, takes no file args.
# (A repo that inherits the parent hook — no local pre-merge override — passes.)
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.linters.sweatfile;

  check = pkgs.writeShellApplication {
    name = "conformist-sweatfile";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      gnused
    ];
    text = ''
      [ -f sweatfile ] || exit 0

      line=$(sed 's/#.*$//' sweatfile | grep -E '^[[:space:]]*pre-merge[[:space:]]*=' | head -1 || true)
      if [ -z "$line" ]; then
        echo "sweatfile: no [hooks].pre-merge override (inherits the parent hook)"
        exit 0
      fi

      val=$(printf '%s' "$line" | sed -E 's/^[^=]*=[[:space:]]*//; s/[[:space:]]*$//')
      if [ "$val" != '"just"' ]; then
        echo "sweatfile: [hooks].pre-merge must be \"just\" — the default recipe is the CI lane (eng-design_patterns-justfile(7)); found: $val" >&2
        exit 1
      fi
      echo "sweatfile: [hooks].pre-merge is \"just\""
    '';
  };
in
{
  options.linters.sweatfile = {
    enable = lib.mkEnableOption "the sweatfile pre-merge='just' whole-tree check";
  };

  config = lib.mkIf cfg.enable {
    settings.linter.sweatfile = {
      command = lib.getExe check;
      includes = [ "sweatfile" ];
      passes-files = false;
    };
  };
}
