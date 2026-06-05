# Sandbox-safe packaging for a script-based linter command (conformist#19).
#
# A linter `command` / `repair-command` that is a hand-written script copied into
# a derivation must have its shebang resolved to an absolute /nix/store
# interpreter, or it cannot exec inside the pure-nix `conformist check` sandbox,
# where /usr/bin/env is absent. The failure is masked outside the sandbox (a dev
# shell has /usr/bin/env), so a `cp script + wrapProgram` that forgets
# `patchShebangs` appears to work until the sandboxed `checks.<name>` gate runs.
#
# Prefer this helper over hand-rolling that derivation. It installs the script,
# runs `patchShebangs` (the fix), and optionally locks a PATH via `wrapProgram`.
# Unlike `pkgs.writeShellApplication`, it wraps an existing script file verbatim
# — it does not inject `set -euo pipefail`, which could change the behavior of a
# script not written for it.
#
# Usage:
#   conformist.lib.writeCheckScript pkgs {
#     name = "lint-foo";
#     src = ./scripts/lint-foo;        # may begin with #!/usr/bin/env bash
#     runtimeInputs = [ pkgs.jq ];     # optional; prepended to PATH
#   }
pkgs:
{
  name,
  src,
  runtimeInputs ? [ ],
}:
let
  inherit (pkgs) lib;
in
pkgs.runCommand name
  {
    nativeBuildInputs = [ pkgs.makeWrapper ];
  }
  ''
    install -Dm755 ${src} $out/bin/${name}
    # Resolve #!/usr/bin/env (and friends) to a /nix/store interpreter so the
    # script execs inside the sandboxed `conformist check` derivation.
    patchShebangs $out/bin/${name}
    ${lib.optionalString (runtimeInputs != [ ]) ''
      wrapProgram $out/bin/${name} --prefix PATH : ${lib.makeBinPath runtimeInputs}
    ''}
  ''
