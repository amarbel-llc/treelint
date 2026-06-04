# eng-versioning(7) conformance as a whole-tree conformist linter
# (passes-files=false): verifies version.env at the tree root declares
# `export <REPO>_VERSION=<semver>`, where <REPO> is the repo name (derived from
# go.mod's module path) uppercased. It reads only committed files (version.env,
# go.mod), so it runs in the sandboxed checks.formatting derivation as well as
# `nix fmt`. See amarbel-llc/conformist#14 and eng-versioning(7).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.linters.eng-versioning;

  check = pkgs.writeShellApplication {
    name = "conformist-eng-versioning";
    runtimeInputs = with pkgs; [
      coreutils
      gawk
      gnugrep
    ];
    text = ''
      # cwd is the tree root (conformist runs whole-tree checks there); this
      # check takes no file arguments.
      [ -f version.env ] || {
        echo "eng-versioning(7): version.env missing at tree root" >&2
        exit 1
      }
      [ -f go.mod ] || {
        echo "eng-versioning(7): go.mod missing; cannot derive the version key" >&2
        exit 1
      }

      module=$(awk '/^module /{print $2; exit}' go.mod)
      repo=''${module##*/}
      expected=$(printf '%s' "$repo" | tr '[:lower:]-' '[:upper:]_')_VERSION

      if ! grep -qE "^export ''${expected}=[0-9]+\.[0-9]+\.[0-9]+" version.env; then
        found=$(grep -oE '^export [A-Za-z0-9_]+_VERSION' version.env | head -1 || true)
        echo "eng-versioning(7): version.env must declare 'export ''${expected}=<semver>' (found: ''${found:-none})" >&2
        exit 1
      fi

      echo "eng-versioning(7): ''${expected} present and well-formed"
    '';
  };
in
{
  options.linters.eng-versioning = {
    enable = lib.mkEnableOption "the eng-versioning(7) whole-tree conformance check";
  };

  config = lib.mkIf cfg.enable {
    settings.linter.eng-versioning = {
      command = lib.getExe check;
      includes = [ "version.env" ];
      passes-files = false;
    };
  };
}
