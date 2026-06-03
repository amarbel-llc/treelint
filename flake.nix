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

    # `nix fmt` driver. Config lives in ./treefmt.nix.
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "igloo";
    };
  };

  outputs =
    {
      self,
      igloo,
      nixpkgs-master,
      utils,
      treefmt-nix,
    }:
    utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import igloo { inherit system; };
        pkgs-master = import nixpkgs-master { inherit system; };

        treefmtEval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;

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
      in
      {
        packages = {
          default = conformist;
          conformist = conformist;
        };

        # `nix fmt` writes; `checks.formatting` is the sandboxed read-only gate
        # built by `just lint-fmt`.
        formatter = treefmtEval.config.build.wrapper;
        checks.formatting = treefmtEval.config.build.check self;

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
    );
}
