# ruff-check as a conformist LINTER (RFC 0001 §4). The check action is
# `ruff check` (read-only, exits non-zero on findings); the repair action is
# `ruff check --fix` (autofix in repair mode). treefmt-nix shipped this as a
# "formatter" that always ran `check --fix`; conformist splits the two so
# `conformist check` reports without writing (conformist#6).
{
  config,
  lib,
  mkLinterModule,
  ...
}:
let
  cfg = config.linters.ruff-check;
in
{
  meta.maintainers = [ ];

  imports = [
    (mkLinterModule {
      name = "ruff-check";
      package = "ruff";
      mainProgram = "ruff";
      args = [ "check" ];
      repairArgs = [
        "check"
        "--fix"
      ];
      includes = [
        "*.py"
        "*.pyi"
      ];
    })
  ];

  options.linters.ruff-check = {
    extendSelect = lib.mkOption {
      description = ''
        --extend-select options
      '';
      type = lib.types.listOf lib.types.str;
      example = [ "I" ];
      default = [ ];
    };
  };

  config = lib.mkIf cfg.enable {
    settings.linter.ruff-check = lib.mkIf ((builtins.length cfg.extendSelect) != 0) {
      options = lib.mkAfter [
        "--extend-select"
        (lib.concatStringsSep "," cfg.extendSelect)
      ];
    };
  };
}
