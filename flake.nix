{
  description = "conformist: the linter and formatter multiplexer";

  inputs = {
    # amarbel-llc/nixpkgs fork. Its overlay carries a patched
    # buildGoApplication that auto-injects `-X main.version` (read from
    # version.env in the module dir) and `-X main.commit` (from src.rev),
    # so no per-repo ldflags wiring is needed. See eng-versioning(7) and
    # amarbel-llc/nixpkgs#31.
    igloo.url = "github:amarbel-llc/igloo";

    # Pinned plain nixpkgs, source of the Go dev tooling in the devShell
    # (gofumpt/golangci-lint/gopls). The Go *toolchain* itself now comes from
    # igloo's `pkgs.go` so the buildGoApplication and native (godyn) backends
    # share one compiler — see igloo#29 / buildGoAuto.
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

        # bga (buildGoApplication) build — the opt-in, ca-derivations-free backend
        # behind `.#conformist-bga`. No longer the default (the godyn build is).
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
          # igloo's pkgs.go (1.26.3), shared with the native (godyn) backend so
          # both build paths use one compiler (igloo#29). go.mod is `go 1.26.1`;
          # GOTOOLCHAIN = "local" pins to pkgs.go rather than fetching a toolchain.
          go = pkgs.go;
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
        # Man pages factory, parameterised by the conformist binary used to run
        # `gen-man` — so each backend's package bundles man pages built with its
        # own binary, without dragging in the other backend.
        mkManpages =
          bin:
          pkgs.runCommand "conformist-manpages"
            {
              nativeBuildInputs = [
                pkgs.scdoc
                bin
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

        # Man pages per backend: the default (godyn) package needs no bga build,
        # and the bga fallback needs no ca-derivations.
        manpages = mkManpages conformist-dev;
        manpagesBga = mkManpages conformistBin;

        # The shipped package (DEFAULT): the godyn (native) binary plus its man
        # pages. After the full switch to the godyn backend, `nix build`,
        # `nix run .`, and `.#conformist` all resolve here; the bga build is the
        # opt-in `.#conformist-bga` below. `meta.mainProgram` keeps `nix run` /
        # `lib.getExe` resolving to bin/conformist.
        conformist = pkgs.symlinkJoin {
          name = "conformist";
          paths = [
            conformist-dev
            manpages
          ];
          meta = (conformist-dev.meta or { }) // {
            mainProgram = "conformist";
          };
        };

        # Opt-in bga package: the single input-addressed buildGoApplication
        # derivation + bga-built man pages. ca-derivations-free, so consumers
        # without that experimental feature (or who want the cold/release-faster
        # single-derivation build) can `nix build .#conformist-bga`. See the
        # backend bench (`just debug-bench-backends`) for the tradeoffs.
        conformist-bga = pkgs.symlinkJoin {
          name = "conformist-bga";
          paths = [
            conformistBin
            manpagesBga
          ];
          meta = (conformistBin.meta or { }) // {
            mainProgram = "conformist";
          };
        };

        # Native (godyn) build of the bare binary, driven by the committed
        # godyn-graph.json (igloo#29). buildGoAuto with strategy = "dev" selects
        # igloo's per-package godyn backend (`go tool compile`/`link` directly,
        # no `go build`). This is now the DEFAULT backend: the `conformist` join
        # above bundles it with man pages, and `.#conformist-dev` exposes the bare
        # binary (no man pages) for the fast inner loop and the backend bench. Its
        # per-package outputs are content-addressed, so building it requires the
        # ca-derivations feature; the input-addressed bga build is `.#conformist-bga`.
        #
        # subPackages / GOTOOLCHAIN are buildGoApplication-only knobs and so live
        # under bgaArgs (the godyn backend ignores them: its scope is the graph,
        # and it calls the toolchain directly). go = pkgs.go matches conformistBin
        # so both backends share one compiler. version/commit are auto-injected
        # from version.env + self.rev — no ldflags here.
        conformist-dev = pkgs.buildGoAuto {
          pname = "conformist";
          src = self;
          graphFile = ./godyn-graph.json;
          modules = ./gomod2nix.toml;
          strategy = "dev";
          bgaArgs = {
            pwd = ./.;
            subPackages = [ "." ];
            go = pkgs.go;
            GOTOOLCHAIN = "local";
            doCheck = false;
          };
        };

        # conformist self-consuming its own module. Replaces the former
        # treefmt-nix `treefmtEval`. The bare godyn binary (conformist-dev) is used
        # here — the formatter wrapper and check gate only need the executable, and
        # reusing the default backend avoids a separate bga build during lint.
        # `package` is required because conformist is not in nixpkgs.
        conformistEval = conformistLib.evalModule pkgs {
          imports = [ ./nix/conformist.nix ];
          package = conformist-dev;
        };

        # IMPURE self-check config: git-state whole-tree checks (e.g. git-remotes)
        # that need a live .git and so cannot run in the sandboxed
        # checks.formatting. `just check-worktree` builds this config and runs
        # `conformist check` against the working tree. See nix/conformist-impure.nix.
        conformistImpureEval = conformistLib.evalModule pkgs {
          imports = [ ./nix/conformist-impure.nix ];
          package = conformist-dev;
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
          # Default is now the godyn (native) build + man pages.
          default = conformist;
          conformist = conformist;
          # Opt-in bga (buildGoApplication) build + man pages: ca-derivations-free,
          # a single input-addressed derivation. The former default backend.
          conformist-bga = conformist-bga;
          # The bare godyn binary for the fast edit loop and the backend bench
          # (`nix build .#conformist-dev`, `.#conformist-dev.passthru.bga`); no man
          # pages. See conformist-dev above.
          conformist-dev = conformist-dev;
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

          # Regression test for the sandbox-safe script-linter helper
          # (conformist#19). Packages an example `#!/usr/bin/env bash` script via
          # writeCheckScript and EXECUTES it inside the build sandbox — which has
          # no /usr/bin/env — so a missing patchShebangs would make exec fail here
          # (the very failure #19 describes), failing the build. This is the
          # dogfood proof that the helper produces sandbox-safe scripts.
          write-check-script =
            let
              example = conformistLib.writeCheckScript pkgs {
                name = "example-check";
                src = pkgs.writeText "example-check" "#!/usr/bin/env bash\necho ok\n";
                runtimeInputs = [ pkgs.coreutils ];
              };
            in
            pkgs.runCommand "conformist-write-check-script-test" { } ''
              got=$(${example}/bin/example-check) || {
                echo "write-check-script: example failed to exec in the pure sandbox (#19 regression)" >&2
                exit 1
              }
              [ "$got" = "ok" ] || {
                echo "write-check-script: unexpected output '$got'" >&2
                exit 1
              }
              touch $out
            '';
        };

        devShells.default = pkgs-master.mkShell {
          packages = [
            # mkGoEnv puts the gomod2nix-regen `go` wrapper + the gomod2nix CLI
            # on PATH, so `just build-gomod2nix` / `just update-go` work.
            (pkgs.mkGoEnv { pwd = ./.; })
            # igloo's pkgs.go (1.26.3), matching conformistBin + the godyn
            # backend (igloo#29). godyn-gen runs `go list -deps -json` against
            # this go, so `just build-godyn-graph` regenerates the committed graph.
            pkgs.go
            pkgs.godyn-gen
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
