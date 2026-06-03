# Eval-only smoke test for the program (formatter) and linter registries.
#
# For every programs/<name>.nix and linters/<name>.nix, enable it in isolation
# and generate its config file. Generating the config forces full module
# evaluation — every option type-check, every `config = mkIf cfg.enable` block,
# the package-attr resolution (`mkPackageOption pkgs <name>` forces pkgs.<name>
# to EXIST, though not to build), and the TOML serialization. So this catches
# unknown options, wrong types, missing-required-`includes`, and wrong package
# attr names, without building each underlying tool.
#
# It does NOT prove a tool's package builds or that its mainProgram/binary name
# is correct — those need a real build (see the dogfooded set in flake.nix and
# the representative complex ports verified separately).
#
# Usage (see flake.nix): import ./nix/checks.nix { inherit pkgs; lib = conformistLib; }
{
  pkgs,
  lib,
}:
let
  toFormatterConfig =
    name:
    lib.mkConfigFile pkgs {
      # enableDefaultExcludes pulls in a large static list that is irrelevant to
      # per-tool schema validation; turn it off to keep each generated file lean.
      enableDefaultExcludes = false;
      programs.${name}.enable = true;
    };

  toLinterConfig =
    name:
    lib.mkConfigFile pkgs {
      enableDefaultExcludes = false;
      linters.${name}.enable = true;
    };

  formatterConfigs = builtins.listToAttrs (
    map (name: {
      name = "formatter-${name}";
      value = toFormatterConfig name;
    }) lib.programs.names
  );

  linterConfigs = builtins.listToAttrs (
    map (name: {
      name = "linter-${name}";
      value = toLinterConfig name;
    }) lib.linters.names
  );
in
formatterConfigs // linterConfigs
