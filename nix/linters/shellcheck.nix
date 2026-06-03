# shellcheck as a conformist LINTER (RFC 0001 §4), not a formatter.
#
# treefmt-nix ships shellcheck under programs/ (a "formatter" that relies on a
# no-op rewrite plus its exit code). conformist models it correctly: shellcheck is
# a read-only check tool — its `command` inspects files and exits non-zero on
# findings, and it has no autofix (no repair action), so it is a no-op in
# repair mode. Configured under `linters.shellcheck`, emitting [linter.shellcheck].
{
  config,
  lib,
  mkLinterModule,
  ...
}:
let
  cfg = config.linters.shellcheck;
in
{
  meta.maintainers = [ "zimbatm" ];

  options.linters.shellcheck = {
    external-sources = lib.mkEnableOption "Allow sources outside of `includes`";
    extra-checks = lib.mkOption {
      description = ''
        List of optional checks to enable (or "all")
      '';
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "all" ];
    };
    severity = lib.mkOption {
      description = ''
        Minimum severity of errors to consider ("error", "warning", "info", "style")
      '';
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
    source-path = lib.mkOption {
      description = ''
        Specify path when looking for sourced files ("SCRIPTDIR" for script's dir)
      '';
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
  };

  imports = [
    (mkLinterModule {
      name = "shellcheck";
      includes = [
        "*.sh"
        "*.bash"
        # direnv
        "*.envrc"
        "*.envrc.*"
      ];
    })
  ];

  config = lib.mkIf cfg.enable {
    settings.linter.shellcheck.options =
      (lib.optional cfg.external-sources "--external-sources")
      ++ (lib.optional (
        cfg.extra-checks != [ ]
      ) "--enable=${lib.strings.concatStringsSep "," cfg.extra-checks}")
      ++ (lib.optional (cfg.severity != null) "--severity=${cfg.severity}")
      ++ (lib.optional (cfg.source-path != null) "--source-path=${cfg.source-path}");
  };
}
