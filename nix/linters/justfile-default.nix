# eng-design_patterns-justfile(7) DEFAULT RECIPE: `default` must be the first
# recipe in the file. Whole-tree check (passes-files=false): reads the justfile,
# takes no file arguments. See eng-design_patterns-justfile(7).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.linters.justfile-default;

  check = pkgs.writeShellApplication {
    name = "conformist-justfile-default";
    runtimeInputs = with pkgs; [
      coreutils
      gawk
    ];
    text = ''
      [ -f justfile ] || {
        echo "justfile-default: justfile missing at tree root" >&2
        exit 1
      }

      # First recipe = first column-0 line that is a recipe (not a comment,
      # blank, [attribute], or `name :=` assignment) and contains a `:`.
      first=$(awk '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*$/ { next }
        /^\[/ { next }
        /^[A-Za-z_]/ {
          if ($0 ~ /:=/) next
          if ($0 !~ /:/) next
          n = $0
          sub(/[[:space:]:].*/, "", n)
          print n
          exit
        }
      ' justfile)

      if [ "$first" != "default" ]; then
        echo "justfile-default: the first recipe must be 'default' (found: '$first') — eng-design_patterns-justfile(7)" >&2
        exit 1
      fi
      echo "justfile-default: 'default' is the first recipe"
    '';
  };
in
{
  options.linters.justfile-default = {
    enable = lib.mkEnableOption "the 'default is the first recipe' whole-tree check (eng-design_patterns-justfile(7))";
  };

  config = lib.mkIf cfg.enable {
    settings.linter.justfile-default = {
      command = lib.getExe check;
      includes = [ "justfile" ];
      passes-files = false;
    };
  };
}
