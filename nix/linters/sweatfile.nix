# A spinclass sweatfile must be present at the repo root and pass
# `spinclass validate` (structural + semantic validation of the sweatfile
# hierarchy). Whole-tree check (passes-files=false): takes no file arguments.
#
# IMPURE: `spinclass` is installed in the user profile (not nixpkgs) and validate
# walks the live sweatfile hierarchy, so this can't run in the sandboxed
# checks.formatting. It lives in nix/conformist-impure.nix and runs via
# `just lint-worktree`. writeShellScriptBin (not writeShellApplication) so the
# script inherits the caller's PATH, where `spinclass` resolves.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.linters.sweatfile;

  check = pkgs.writeShellScriptBin "conformist-sweatfile" ''
    [ -f sweatfile ] || {
      echo "sweatfile: a spinclass sweatfile is expected at the tree root but is missing" >&2
      exit 1
    }
    if ! command -v spinclass >/dev/null 2>&1; then
      echo "sweatfile: present, but spinclass is not on PATH; skipping validation"
      exit 0
    fi
    exec spinclass validate
  '';
in
{
  options.linters.sweatfile = {
    enable = lib.mkEnableOption "the sweatfile presence + `spinclass validate` whole-tree check";
  };

  config = lib.mkIf cfg.enable {
    settings.linter.sweatfile = {
      command = lib.getExe check;
      # Gate on a file that is always present; the script enforces sweatfile
      # presence itself (so a missing sweatfile is a finding, not a no-run).
      includes = [ "flake.nix" ];
      passes-files = false;
    };
  };
}
