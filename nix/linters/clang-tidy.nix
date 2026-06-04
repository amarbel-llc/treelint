# clang-tidy as a conformist LINTER (RFC 0001 §4). The check action is
# `clang-tidy` (reports diagnostics, exits non-zero on findings); the repair
# action adds `--fix` (applies fixes in repair mode). treefmt-nix shipped this
# as a "formatter" that always passed `--fix`; conformist splits the two
# (conformist#6). The config-file / compile-commands / quiet flags apply to both
# invocations.
{
  config,
  mkLinterModule,
  lib,
  ...
}:
let
  cfg = config.linters.clang-tidy;
  sharedFlags =
    lib.optional (cfg.configFile != null) "--config-file=${cfg.configFile}"
    ++ lib.optional (cfg.compileCommandsPath != null) "-p=${cfg.compileCommandsPath}"
    ++ lib.optional cfg.quiet "--quiet";
in
{
  meta.maintainers = [ ];

  imports = [
    (mkLinterModule {
      name = "clang-tidy";
      package = "clang-tools";
      mainProgram = "clang-tidy";
      repairArgs = [ "--fix" ];
      includes = [
        "*.c"
        "*.cc"
        "*.cpp"
        "*.h"
        "*.hh"
        "*.hpp"
        "*.glsl"
        "*.vert"
        ".tesc"
        ".tese"
        ".geom"
        ".frag"
        ".comp"
      ];
    })
  ];

  options.linters.clang-tidy = {
    configFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      description = "Specify the path of .clang-tidy or custom config file";
      default = null;
      example = "/some/path/myTidyConfigFile";
    };
    compileCommandsPath = lib.mkOption {
      type = with lib.types; nullOr (either path str);
      description = "used to read a compile command database";
      default = null;
      example = "/my/cmake/build/directory";
    };
    quiet = lib.mkOption {
      type = lib.types.bool;
      description = "Run clang-tidy in quiet mode";
      default = true;
    };
  };

  config = lib.mkIf (cfg.enable && sharedFlags != [ ]) {
    settings.linter.clang-tidy = {
      options = lib.mkAfter sharedFlags;
      "repair-options" = lib.mkAfter sharedFlags;
    };
  };
}
