# tommy codegen as a conformist linter (check + repair).
#
# Repos that use tommy's code generator carry committed `*_tommy.go` files
# produced by `//go:generate tommy generate` directives. This linter folds that
# codegen into conformist:
#
#   - CHECK (`conformist check`): runs `tommy generate --check` for every source
#     file carrying the directive, failing on stale output (the same skew/
#     staleness guard `tommy generate --check` implements, keyed on the version
#     header tommy stamps into the generated file).
#   - REPAIR (`conformist` / `nix fmt` / `conformist --commit`): runs
#     `tommy generate`, rewriting the `*_tommy.go` files. In the `--commit`
#     auto-fix flow conformist commits whatever repair changed, so regenerated
#     codegen lands in the `chore: conformist fmt+fix` commit.
#
# Whole-tree check (passes-files = false): it walks the tree for the directive
# itself rather than taking conformist's matched file list, so a touched source
# .go file (the codegen INPUT) triggers a re-check even though its `*_tommy.go`
# OUTPUT did not change.
#
# Toolchain by ambient PATH, deliberately self-gating. `tommy generate` shells
# out to the Go toolchain (go/packages analysis), which cannot run in a
# read-only / network-free sandbox. The script therefore resolves `tommy` and
# `go` from the AMBIENT PATH (NOT baked into runtimeInputs) and exits 0 (skip)
# when either is missing. So in conformist's sandboxed `checks.formatting` lane
# the linter is a safe no-op, while the impure repair / `nix fmt` / devshell
# lanes — which put the pinned tommy + go on PATH — get the real check and
# regen. Provide that toolchain on PATH wherever you want this linter to act.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.linters.tommy-codegen;

  # One script, two modes: `--check` (read-only diff) or default (regen, writes).
  # Walks the tree for `//go:generate tommy generate` directives and runs tommy
  # with GOFILE + cwd set per file, mirroring `go generate` but scoped to tommy.
  driver = pkgs.writeShellApplication {
    name = "conformist-tommy-codegen";
    # NOTE: tommy + go come from the ambient PATH (self-gating); only the
    # tree-walking utilities are pinned here.
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      gnugrep
    ];
    text = ''
      mode="repair"
      if [ "''${1:-}" = "--check" ]; then
        mode="check"
      fi

      if ! command -v tommy >/dev/null 2>&1; then
        echo "tommy-codegen: tommy not on PATH; skipping" >&2
        exit 0
      fi
      if ! command -v go >/dev/null 2>&1; then
        echo "tommy-codegen: go not on PATH; skipping" >&2
        exit 0
      fi

      status=0
      while IFS= read -r f; do
        dir=$(dirname "$f")
        base=$(basename "$f")
        if [ "$mode" = "check" ]; then
          ( cd "$dir" || exit 1; GOFILE="$base" tommy generate --check; ) || status=1
        else
          ( cd "$dir" || exit 1; GOFILE="$base" tommy generate; ) || status=1
        fi
      done < <(grep -rIl --include='*.go' 'go:generate tommy generate' . 2>/dev/null | grep -v '/result' || true)

      exit "$status"
    '';
  };
in
{
  options.linters.tommy-codegen = {
    enable = lib.mkEnableOption "the tommy codegen check + repair whole-tree linter";
  };

  config = lib.mkIf cfg.enable {
    settings.linter.tommy-codegen = {
      command = lib.getExe driver;
      options = [ "--check" ];
      "repair-command" = lib.getExe driver;
      # Gate on Go sources so a touched codegen input re-triggers the check; the
      # script ignores the file list and walks the tree itself.
      includes = [
        "*.go"
        "**/*.go"
      ];
      passes-files = false;
    };
  };
}
