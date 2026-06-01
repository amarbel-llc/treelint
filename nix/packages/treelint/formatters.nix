# Formatter binaries the integration/unit test suite shells out to. Mirrors
# numtide/treefmt's nix/packages/treefmt/formatters.nix, trimmed to the
# formatters actually referenced by test/examples/treelint.toml plus jujutsu
# for the jj-backed walk tests. Imported into the devShell in flake.nix so
# `just test-go` (which runs `nix develop --command go test ./...`) finds them
# on PATH. gofmt/just/shellcheck are already provided by the base devShell.
pkgs:
with pkgs; [
  # real formatters referenced by the default config (test/examples/treelint.toml)
  alejandra
  black
  deadnix
  dos2unix
  opentofu
  ormolu
  prettier
  rufo
  rustfmt
  shfmt
  yamlfmt

  # jj-backed walk tests (TestJujutsu, TestJujutsuReader)
  jujutsu

  # test-only formatter helpers used by cmd/root_test.go
  (writeShellApplication {
    name = "test-fmt-append";
    text = ''
      VALUE="$1"
      shift

      # append value to each file
      for FILE in "$@"; do
          echo "$VALUE" >> "$FILE"
      done
    '';
  })
  (writeShellApplication {
    name = "test-fmt-modtime";
    text = ''
      VALUE="$1"
      shift

      # set the modtime on each file
      for FILE in "$@"; do
          touch -t "$VALUE" "$FILE"
      done
    '';
  })
  (writeShellApplication {
    name = "test-fmt-delayed-append";
    text = ''
      DELAY="$1"
      shift

      # sleep first
      sleep "$DELAY"

      test-fmt-append "$@"
    '';
  })
  (writeShellApplication {
    name = "test-fmt-only-one-file-at-a-time";
    text = ''
      if [ $# -ne 1 ]; then
        echo "I only support formatting exactly 1 file at a time"
        exit 1
      fi

      test-fmt-append "suffix" "$1"
    '';
  })
]
