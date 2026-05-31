# treelint justfile. Conventions: eng-design_patterns-justfile(7),
# eng-versioning(7). `default` runs the full local CI lane.

default: validate lint build test

# --- validate (cheap pre-build gate) ---

validate: validate-devshell

# The devshell must evaluate and build before anything else is worth trying.
validate-devshell:
    nix build --no-link .#devShells.{{ arch() }}-linux.default

# --- lint ---

lint: lint-fmt

# Read-only formatting gate via the treefmt-nix `checks.formatting` derivation
# (the sandboxed counterpart to the writing `nix fmt`).
lint-fmt:
    #!/usr/bin/env bash
    set -euo pipefail
    system=$(nix eval --raw --impure --expr 'builtins.currentSystem')
    nix build ".#checks.${system}.formatting" --no-link --print-build-logs

# --- build ---

build: build-gomod2nix build-go build-nix

# Regenerate gomod2nix.toml from go.mod/go.sum. Run after changing deps.
build-gomod2nix:
    nix develop --command gomod2nix

# Out-of-nix go build for a fast inner loop. Version/commit stay dev/unknown
# here; the nix build injects the real values (eng-versioning(7)).
build-go: build-gomod2nix
    nix develop --command go build -o build/treelint .

build-nix:
    nix build --show-trace

run-nix *ARGS:
    nix run . -- {{ ARGS }}

# --- test ---

test: test-go

test-go:
    nix develop --command go test ./...

# --- format ---

codemod-fmt: codemod-fmt-treefmt

codemod-fmt-treefmt:
    nix fmt

# --- maintenance ---

update-go: && build-gomod2nix
    nix develop --command go mod tidy

[group("maintenance")]
bump-version new_version:
    sed -E -i "s/^(export TREELINT_VERSION)=.*/\1={{ new_version }}/" version.env

[group("maintenance")]
tag message:
    #!/usr/bin/env bash
    set -euo pipefail
    . version.env
    tag="v${TREELINT_VERSION:?missing TREELINT_VERSION in version.env}"
    git tag -s -m "{{ message }}" "$tag"
    echo "Created tag: $tag"
    git push origin "$tag"
    echo "Pushed $tag"
    git tag -v "$tag"

[group("maintenance")]
release new_version:
    #!/usr/bin/env bash
    set -euo pipefail

    # Release only from the default branch.
    branch=$(git rev-parse --abbrev-ref HEAD)
    if [[ "$branch" != "main" ]]; then
        echo "release only allowed from main (on '$branch')" >&2
        exit 1
    fi

    # Generate the changelog BEFORE bump-version — the release-bump commit
    # MUST NOT appear in the changelog it announces.
    prev=$(git tag --sort=-v:refname -l "v*" | head -1)
    header="release v{{ new_version }}"
    if [[ -n "$prev" ]]; then
        summary=$(git log --format='- %s' "$prev"..HEAD)
        msg="$header"$'\n\n'"$summary"
    else
        msg="$header"
    fi

    just bump-version "{{ new_version }}"
    git add version.env
    git commit -m "$header"

    just tag "$msg"

    # gh release create is MUST; artifact upload is MAY.
    gh release create "v{{ new_version }}" --title "$header" --notes "$msg"

# --- clean ---

clean: clean-build

clean-build:
    rm -rf result build/
