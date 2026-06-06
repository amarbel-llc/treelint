# eng-versioning(7) "Deprecated alternatives" as a whole-tree conformist linter
# (passes-files=false): flags deprecated version SOURCES that should migrate to
# version.env — a `version.txt` at the repo root, and a named version let-binding
# in flake.nix (e.g. `moxyVersion = "0.4.10";`). It reads only committed files
# (version.txt, flake.nix), so it runs in the sandboxed checks.formatting
# derivation as well as `nix fmt`.
#
# Scope matches the manpage's "Deprecated alternatives" subsection: version.txt
# and the flake.nix named-variable pattern. The third entry there (hardcoded
# version strings scattered across files) is an open-ended anti-pattern, not a
# single detectable source, so it is intentionally out of scope. Note the bash
# original also flagged a bare `VERSION` file, but the manpage does not list it —
# this rule follows the manpage. See amarbel-llc/conformist#14 and
# eng-versioning(7) SINGLE VERSION SOURCE OF TRUTH (Deprecated alternatives).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.linters.eng-versioning-deprecated-file;

  check = pkgs.writeShellApplication {
    name = "conformist-eng-versioning-deprecated-file";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
    ];
    text = ''
      # cwd is the tree root (conformist runs whole-tree checks there); this
      # check takes no file arguments.
      fail=0

      # A bare-semver `version.txt` at the repo root is deprecated; migrate to
      # version.env (rename the file + wrap the value as `export <REPO>_VERSION=`).
      if [ -f version.txt ]; then
        echo "eng-versioning(7) Deprecated alternatives: version.txt at the repo root is deprecated; rename it to version.env and wrap the value as 'export <REPO>_VERSION=<semver>'" >&2
        fail=1
      fi

      # A named version let-binding in flake.nix (e.g. `moxyVersion = "0.4.10";`)
      # is deprecated; extract the value into version.env and read it via the
      # builtins.match pattern. grep prints the offending line(s) to stderr.
      if [ -f flake.nix ] && grep -nE '[A-Za-z][A-Za-z0-9_]*[Vv]ersion[[:space:]]*=[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+"' flake.nix >&2; then
        echo "eng-versioning(7) Deprecated alternatives: a named version let-binding in flake.nix is deprecated; move the value into version.env and read it via the builtins.match pattern" >&2
        fail=1
      fi

      if [ "$fail" -ne 0 ]; then
        exit 1
      fi
      echo "eng-versioning(7): no deprecated version sources (no version.txt, no named version var in flake.nix)"
    '';
  };
in
{
  options.linters.eng-versioning-deprecated-file = {
    enable = lib.mkEnableOption "the eng-versioning(7) deprecated version-source whole-tree check";
  };

  config = lib.mkIf cfg.enable {
    settings.linter.eng-versioning-deprecated-file = {
      command = lib.getExe check;
      includes = [
        "flake.nix"
        "version.txt"
      ];
      passes-files = false;
    };
  };
}
