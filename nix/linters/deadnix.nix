# deadnix as a conformist LINTER (RFC 0001 §4). The check action is `deadnix`
# (reports dead Nix code, exits non-zero on findings); the repair action is
# `deadnix --edit` (removes it in repair mode). treefmt-nix shipped this as a
# "formatter" that always ran `--edit`; conformist splits the two (conformist#6).
#
# The no-lambda-arg / no-lambda-pattern-names / no-underscore flags scope what
# deadnix considers dead, so they apply to BOTH the check and the repair
# invocation (appended to options and repair-options alike).
{
  lib,
  config,
  mkLinterModule,
  ...
}:
let
  cfg = config.linters.deadnix;
  scopeFlags =
    (lib.optional cfg.no-lambda-arg "--no-lambda-arg")
    ++ (lib.optional cfg.no-lambda-pattern-names "--no-lambda-pattern-names")
    ++ (lib.optional cfg.no-underscore "--no-underscore");
in
{
  meta.maintainers = [ ];

  imports = [
    (mkLinterModule {
      name = "deadnix";
      repairArgs = [ "--edit" ];
      includes = [ "*.nix" ];
    })
  ];

  options.linters.deadnix = {
    no-lambda-arg = lib.mkEnableOption "Don't check lambda parameter arguments";
    no-lambda-pattern-names = lib.mkEnableOption "Don't check lambda attrset pattern names (don't break nixpkgs callPackage)";
    no-underscore = lib.mkEnableOption "Don't check any bindings that start with a _";
  };

  config = lib.mkIf (cfg.enable && scopeFlags != [ ]) {
    settings.linter.deadnix = {
      options = lib.mkAfter scopeFlags;
      "repair-options" = lib.mkAfter scopeFlags;
    };
  };
}
