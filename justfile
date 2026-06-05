# conformist justfile. Conventions: eng-design_patterns-justfile(7),
# eng-versioning(7). `default` runs the full local CI lane.

default: build lint

# --- validate (cheap pre-build gate) ---

validate: validate-devshell

# The devshell must evaluate and build before anything else is worth trying.
validate-devshell:
    nix build --no-link .#devShells.{{ arch() }}-linux.default

# --- lint ---

lint: lint-fmt lint-worktree

# Read-only gate via the self-consumed conformist `checks.formatting` derivation
# (a `conformist check` run; the read-only counterpart to the writing `nix fmt`).
lint-fmt:
    #!/usr/bin/env bash
    set -euo pipefail
    system=$(nix eval --raw --impure --expr 'builtins.currentSystem')
    nix build ".#checks.${system}.formatting" --no-link --print-build-logs

# Non-sandbox lane: run the IMPURE git-state whole-tree checks (e.g. git-remotes)
# against the WORKING TREE, where .git is available. These can't run in the
# sandboxed checks.formatting. Builds the impure config + binary via nix.
lint-worktree:
    #!/usr/bin/env bash
    set -euo pipefail
    cfg=$(nix build --no-link --print-out-paths '.#conformist-impure-config')
    nix run '.#conformist' -- check --config-file "$cfg" --tree-root .

# --- build ---

build: build-gomod2nix build-go build-nix

# Regenerate gomod2nix.toml from go.mod/go.sum. Run after changing deps.
build-gomod2nix:
    nix develop --command gomod2nix

# Out-of-nix go build for a fast inner loop. Version/commit stay dev/unknown
# here; the nix build injects the real values (eng-versioning(7)).
build-go: build-gomod2nix
    nix develop --command go build -o build/conformist .

build-nix:
    nix build --show-trace

run-nix *ARGS:
    nix run . -- {{ ARGS }}

# Build conformist's own generated conformist.toml via self.lib.evalModule and
# cat it, to inspect the emitted [formatter.*] / [linter.*] stanzas. Verifies the
# Nix module's config generation (issue #4) without a full check run.
[group("explore")]
explore-show-config:
    #!/usr/bin/env bash
    set -euo pipefail
    out=$(nix build --no-link --print-out-paths --impure --expr \
      'let f = builtins.getFlake (toString ./.); s = builtins.currentSystem; p = import f.inputs.igloo { system = s; }; in (f.lib.evalModule p { imports = [ ./nix/conformist.nix ]; package = f.packages.${s}.conformist; }).config.build.configFile')
    cat "$out"

# --- test ---

test: test-go

test-go:
    #!/usr/bin/env bash
    # Guard for conformist#15: the cmd integration tests run conformist against
    # $TMPDIR fixtures. The cmd TestMain sets GIT_CEILING_DIRECTORIES and
    # CONFORMIST_CEILING_DIRECTORIES so they can't escape into the worktree, but
    # fail loudly if the working tree is mutated during the run so a regression
    # can't hide in a commit. No `set -e`: capture the test result, always run
    # the tree check (even on test failure), then propagate the test status.
    set -uo pipefail
    before=$(git status --porcelain)
    nix develop --command go test ./...
    rc=$?
    after=$(git status --porcelain)
    if [ "$before" != "$after" ]; then
        echo "test-go: working tree changed during tests — likely conformist#15 (tests escaped tree-root into the worktree). Recover with 'git checkout -- .'." >&2
        exit 1
    fi
    exit "$rc"

# --- format ---

codemod-fmt: codemod-fmt-conformist

codemod-fmt-conformist:
    nix fmt

# --- maintenance ---

update-go: && build-gomod2nix
    nix develop --command go mod tidy

[group("maintenance")]
bump-version new_version:
    sed -E -i "s/^(export CONFORMIST_VERSION)=.*/\1={{ new_version }}/" version.env

[group("maintenance")]
tag message:
    #!/usr/bin/env bash
    set -euo pipefail
    . version.env
    tag="v${CONFORMIST_VERSION:?missing CONFORMIST_VERSION in version.env}"
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
    if [[ "$branch" != "master" ]]; then
        echo "release only allowed from master (on '$branch')" >&2
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
