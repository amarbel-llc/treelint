# tommy as a conformist TOML formatter.
#
# tommy (github:amarbel-llc/tommy) is a CST-based TOML library whose `tommy fmt`
# subcommand normalizes whitespace around `=`, inline-comment spacing, blank
# lines between tables, and trailing whitespace while preserving comments and
# layout on round-trip. Given file paths it rewrites them in place, so it slots
# into conformist's formatter model directly (and the copy-and-diff sandbox lets
# `conformist check` observe drift without writing the source tree).
#
# tommy is NOT in nixpkgs, so unlike the ported treefmt-nix programs this module
# does NOT use `mkFormatterModule` / `mkPackageOption` (which would force a
# non-existent `pkgs.tommy` to resolve and break the eval-only registry smoke
# test in nix/checks.nix). Instead `package` is a nullable option: leave it null
# and the formatter runs the bare `tommy` resolved from PATH (the convention the
# hand-written consumer configs already use); or set it to the tommy flake
# input's package to pin an absolute store path, e.g.
# `programs.tommy.package = inputs.tommy.packages.${system}.default`.
{
  lib,
  config,
  ...
}:
let
  cfg = config.programs.tommy;
in
{
  meta.maintainers = [ ];

  options.programs.tommy = {
    enable = lib.mkEnableOption "tommy (TOML formatter)";

    package = lib.mkOption {
      description = "The tommy package to use. Null runs the bare `tommy` on PATH.";
      type = lib.types.nullOr lib.types.package;
      default = null;
    };

    includes = lib.mkOption {
      description = "Path / file patterns to include";
      type = lib.types.listOf lib.types.str;
      default = [ "*.toml" ];
    };

    excludes = lib.mkOption {
      description = "Path / file patterns to exclude";
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };

    priority = lib.mkOption {
      description = "Priority";
      type = lib.types.nullOr lib.types.int;
      default = null;
    };
  };

  config = lib.mkIf cfg.enable {
    settings.formatter.tommy = {
      command = if cfg.package == null then "tommy" else lib.getExe cfg.package;
      options = [ "fmt" ];
      includes = cfg.includes;
    }
    // (lib.optionalAttrs (cfg.excludes != [ ]) { inherit (cfg) excludes; })
    // (lib.optionalAttrs (cfg.priority != null) { inherit (cfg) priority; });
  };
}
