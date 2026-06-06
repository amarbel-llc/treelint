# and-so-can-you #8: every git remote MUST use SSH (git@.../ssh://), not a
# network transport that needs separate credentials — https://, http://, git://,
# ftp:// all cause auth failures or insecure fetches on push/pull. Local path /
# file:// remotes are left alone (no auth concern). Whole-tree check
# (passes-files=false): reads git state via `git remote -v`, takes no file args.
#
# IMPURE: it needs a live .git, which is NOT present in the sandboxed
# checks.formatting derivation (a /nix/store copy of tracked files). It runs only
# via the non-sandbox `just check-worktree` lane (the conformist-impure config),
# against the working tree. Do not enable it in nix/conformist.nix.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.linters.git-remotes;

  check = pkgs.writeShellApplication {
    name = "conformist-git-remotes";
    runtimeInputs = with pkgs; [
      git
      gawk
      coreutils
      gnused
    ];
    text = ''
      bad=$(git remote -v | awk '$2 ~ /^(https?|git|ftp):\/\// {print $1"\t"$2}' | sort -u)
      if [ -n "$bad" ]; then
        echo "git-remotes(#8): non-SSH remote URL(s) found — use SSH (git@github.com:... or ssh://):" >&2
        printf '%s\n' "$bad" | sed 's/^/  /' >&2
        exit 1
      fi
      echo "git-remotes(#8): all remotes use SSH"
    '';
  };
in
{
  options.linters.git-remotes = {
    enable = lib.mkEnableOption "the git-remotes SSH-only whole-tree check (needs a live .git; non-sandbox lane only)";
  };

  config = lib.mkIf cfg.enable {
    settings.linter.git-remotes = {
      command = lib.getExe check;
      # Gate on a file that is always present and walked, so the check fires once
      # for the tree. The check itself ignores files (passes-files=false).
      includes = [ "flake.nix" ];
      passes-files = false;
    };
  };
}
