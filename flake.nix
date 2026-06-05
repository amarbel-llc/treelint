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

        conformistBin = pkgs.buildGoApplication {
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

        # Man pages, built by Nix per eng-manpages(7) PRINCIPLE 4 (not a justfile
        # recipe, not CI): scdoc compiles the hand-written section-5/7 sources in
        # doc/, and `conformist gen-man` renders the section-1 CLI reference from
        # the cobra command tree (PRINCIPLE 3). This derivation IS the man-page
        # lint — a malformed .scd fails the build. Rendered roff is never committed.
        manpages =
          pkgs.runCommand "conformist-manpages"
            {
              nativeBuildInputs = [
                pkgs.scdoc
                conformistBin
              ];
            }
            ''
              mkdir -p $out/share/man/man1
              # Compile every hand-written scdoc page, deriving its man section
              # from the penultimate extension (e.g. conformist.toml.5.scd ->
              # man5). Any hand-written section (2-9) ships automatically rather
              # than being silently dropped, so the build keeps acting as the
              # man-page lint. Section 1 is owned by `gen-man` (codegen) below, so
              # a stray *.1.scd is reported and skipped rather than racing gen-man
              # over the same man1 page; a misnamed file (no numeric section) is
              # likewise surfaced instead of producing a bogus man<word> dir.
              for f in ${self}/doc/*.scd; do
                [ -e "$f" ] || continue
                page=$(basename "''${f%.scd}") # e.g. conformist.toml.5
                section="''${page##*.}"         # e.g. 5
                case "$section" in
                  [2-9]) ;;
                  *)
                    echo "manpages: skipping $f (section '$section' is not a hand-written man section 2-9; section 1 is codegen)" >&2
                    continue
                    ;;
                esac
                mkdir -p "$out/share/man/man$section"
                scdoc < "$f" > "$out/share/man/man$section/$page"
              done
              # Section 1 (the CLI reference) is codegen from the cobra tree, not scdoc.
              conformist gen-man "$out/share/man/man1"
            '';

        # The shipped package: the binary plus its man pages, merged so that
        # `nix build` produces man pages alongside the binary (eng-manpages(7)).
        # `meta.mainProgram` keeps `nix run`/`lib.getExe` resolving to bin/conformist.
        conformist = pkgs.symlinkJoin {
          name = "conformist";
          paths = [
            conformistBin
            manpages
          ];
          # Preserve the binary's meta (description, license, …) on the shipped
          # package; symlinkJoin would otherwise drop it. mainProgram keeps
          # `nix run`/`lib.getExe` resolving to bin/conformist.
          meta = (conformistBin.meta or { }) // {
            mainProgram = "conformist";
          };
        };

        # conformist self-consuming its own module. Replaces the former
        # treefmt-nix `treefmtEval`. The bare binary (conformistBin) is used here:
        # the formatter wrapper and check gate only need the executable, not the
        # man pages. `package` is required because conformist is not in nixpkgs.
        conformistEval = conformistLib.evalModule pkgs {
          imports = [ ./nix/conformist.nix ];
          package = conformistBin;
        };

        # IMPURE self-check config: git-state whole-tree checks (e.g. git-remotes)
        # that need a live .git and so cannot run in the sandboxed
        # checks.formatting. `just check-worktree` builds this config and runs
        # `conformist check` against the working tree. See nix/conformist-impure.nix.
        conformistImpureEval = conformistLib.evalModule pkgs {
          imports = [ ./nix/conformist-impure.nix ];
          package = conformistBin;
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
          # The compiled man pages on their own, for inspection
          # (`nix build .#manpages`); also bundled into the conformist package.
          inherit manpages;
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
            # scdoc for ad-hoc local man-page preview; the authoritative build
            # is the `manpages` Nix derivation (eng-manpages(7) PRINCIPLE 4).
            pkgs.scdoc
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
