# conformist's IMPURE self-check config: whole-tree checks that need the live
# working tree or host tools (a real .git, or `spinclass` from the user profile)
# and therefore CANNOT run in the sandboxed checks.formatting (which sees only a
# /nix/store copy of tracked files). Consumed by `just lint-worktree`, which runs
# `conformist check` against the working tree. `package` is injected by flake.nix
# (conformistImpureEval). See the non-sandbox lane.
{ ... }:
{
  projectRootFile = "flake.nix";

  # git-remotes needs a live .git; sweatfile runs `spinclass validate` (spinclass
  # is profile-installed, not nixpkgs). Both live here, not in nix/conformist.nix.
  linters.git-remotes.enable = true;
  linters.sweatfile.enable = true;
}
