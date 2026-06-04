# conformist's IMPURE self-check config: git-state whole-tree checks that need a
# live .git and therefore CANNOT run in the sandboxed checks.formatting (which
# sees only a /nix/store copy of tracked files). Consumed by `just check-worktree`,
# which runs `conformist check` against the working tree. `package` is injected by
# flake.nix (conformistImpureEval). See the non-sandbox lane / and-so-can-you #8.
{ ... }:
{
  projectRootFile = "flake.nix";

  # git-remotes needs a live .git, so it lives here, not in nix/conformist.nix.
  linters.git-remotes.enable = true;
}
