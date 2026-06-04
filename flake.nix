{
  description = "conformist: the linter and formatter multiplexer";

  inputs = {
    # amarbel-llc/nixpkgs fork. Its overlay carries a patched
    # buildGoApplication that auto-injects `-X main.version` (read from
    # version.env in the module dir) and `-X main.commit` (from src.rev),
    # so no per-repo ldflags wiring is needed. See eng-versioning(7) and
    # amarbel-llc/nixpkgs#31.
    igloo.url = "github:amarbel-llc/igloo";

    # Pinned plain nixpkgs as the source of go_1_26 (matches go.mod's
    # toolchain directive). Mirrors moxy, the canonical reference.
    nixpkgs-master.url = "github:NixOS/nixpkgs/d233902339c02a9c334e7e593de68855ad26c4cb";

    utils.url = "https://flakehub.com/f/numtide/flake-utils/0.1.102";
  };

  outputs =
    {
      self,
      igloo,
      nixpkgs-master,
      utils,
    }:
    let
      # conformist's own Nix module library (issue #4). Exposed as `self.lib` so
      # downstream flakes can `conformist.lib.evalModule pkgs { ... }`, and
      # consumed below for conformist's own `nix fmt` / `checks.formatting`
      # (self-consumption — conformist no longer depends on treefmt-nix).
      conformistLib = import ./nix;
    in
    (utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import igloo { inherit system; };
        pkgs-master = import nixpkgs-master { inherit system; };

        conformist = pkgs.buildGoApplication {
          pname = "conformist";
          # `src = self` lets the fork's buildGoApplication resolve
          # `-X main.commit` from self.rev and read version.env (carried in
          # src) for `-X main.version`. version + commit are injected
          # automatically — no ldflags here.
          src = self;
          pwd = ./.;
          modules = ./gomod2nix.toml;
          subPackages = [ "." ];
          go = pkgs-master.go_1_26;
          GOTOOLCHAIN = "local";
          # Integration tests need formatter executables on PATH; run them via
          # `just test-go` / bats outside the sandbox, not in the package build.
          doCheck = false;
        };

        # conformist self-consuming its own module. Replaces the former
        # treefmt-nix `treefmtEval`. `package = conformist` is required because
        # conformist is not in nixpkgs (the module has no default package).
        conformistEval = conformistLib.evalModule pkgs {
          imports = [ ./nix/conformist.nix ];
          package = conformist;
        };

        # IMPURE self-check config: git-state whole-tree checks (e.g. git-remotes)
        # that need a live .git and so cannot run in the sandboxed
        # checks.formatting. `just check-worktree` builds this config and runs
        # `conformist check` against the working tree. See nix/conformist-impure.nix.
        conformistImpureEval = conformistLib.evalModule pkgs {
          imports = [ ./nix/conformist-impure.nix ];
          package = conformist;
        };

        # Eval-only smoke test over the full program + linter registries:
        # checks.<sys>.{formatter-<name>,linter-<name>}. Forces module eval +
        # config generation for every ported tool, catching schema breakage
        # without building each tool. See nix/checks.nix.
        registryChecks = import ./nix/checks.nix {
          inherit pkgs;
          lib = conformistLib;
        };
      in
      {
        packages = {
          default = conformist;
          conformist = conformist;
          # The generated config for the impure (git-state) self-checks, consumed
          # by `just check-worktree`.
          conformist-impure-config = conformistImpureEval.config.build.configFile;
        };

        # `nix fmt` writes (repair mode); `checks.formatting` is the sandboxed
        # read-only `conformist check` gate built by `just lint-fmt`. The
        # `formatter-*` / `linter-*` checks are the registry smoke test.
        formatter = conformistEval.config.build.wrapper;
        checks = registryChecks // {
          formatting = conformistEval.config.build.check self;
        };

        devShells.default = pkgs-master.mkShell {
          packages = [
            # mkGoEnv puts the gomod2nix-regen `go` wrapper + the gomod2nix CLI
            # on PATH, so `just build-gomod2nix` / `just update-go` work.
            (pkgs.mkGoEnv { pwd = ./.; })
            pkgs-master.go_1_26
            pkgs-master.gofumpt
            pkgs-master.golangci-lint
            pkgs-master.gopls
            pkgs.just
            # A real linter for dogfooding `conformist check` and for the
            # check/linter test paths (RFC 0001).
            pkgs.shellcheck
          ]
          # Formatter binaries + test-fmt-* helpers the Go test suite shells
          # out to (cmd/root_test.go, format/formatter_test.go). Run via
          # `just test-go`, which evaluates this devShell fresh.
          ++ (import ./nix/packages/conformist/formatters.nix pkgs);
        };
      }
    ))
    // {
      # System-agnostic outputs.

      # The conformist Nix module library: evalModule / submoduleWith /
      # mkConfigFile / mkWrapper, plus the formatter (programs) and linter
      # registries. See nix/default.nix.
      lib = conformistLib;

      # flake-parts module: `perSystem.conformist`. See flake-module.nix.
      flakeModule = ./flake-module.nix;
    };
}
