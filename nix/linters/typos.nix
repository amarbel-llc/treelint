# typos as a conformist LINTER (RFC 0001 §4). The check action is `typos`
# (reports misspellings, exits non-zero on findings); the repair action adds
# `--write-changes` (applies corrections in repair mode). treefmt-nix shipped
# this as a "formatter" that always ran `--write-changes`; conformist splits the
# two (conformist#6).
#
# `--force-exclude` (so typos honours its own ignore config even when conformist
# passes a matched file) and all the tuning flags apply to BOTH invocations.
{
  lib,
  config,
  mkLinterModule,
  ...
}:
let
  cfg = config.linters.typos;
  sharedFlags = [
    "--force-exclude"
  ]
  ++ (lib.optionals (!isNull cfg.threads) [
    "--threads"
    (toString cfg.threads)
  ])
  ++ (lib.optionals (!isNull cfg.locale) [
    "--locale"
    (toString cfg.locale)
  ])
  ++ (lib.optionals (!isNull cfg.configFile) [
    "--config"
    cfg.configFile
  ])
  ++ lib.optional cfg.sort "--sort"
  ++ lib.optional cfg.isolated "--isolated"
  ++ lib.optional cfg.hidden "--hidden"
  ++ lib.optional cfg.noIgnore "--no-ignore"
  ++ lib.optional cfg.noIgnoreDot "--no-ignore-dot"
  ++ lib.optional cfg.noIgnoreGlobal "--no-ignore-global"
  ++ lib.optional cfg.noIgnoreParent "--no-ignore-parent"
  ++ lib.optional cfg.noIgnoreVCS "--no-ignore-vcs"
  ++ lib.optional cfg.binary "--binary"
  ++ lib.optional cfg.noCheckFilenames "--no-check-filenames"
  ++ lib.optional cfg.noCheckFiles "--no-check-files"
  ++ lib.optional cfg.noUnicode "--no-unicode";
in
{
  meta.maintainers = [ "adam-gaia" ];

  imports = [
    (mkLinterModule {
      name = "typos";
      repairArgs = [ "--write-changes" ];
      includes = [ "*" ];
    })
  ];

  options.linters.typos = {
    threads = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      example = 2;
      description = "The approximate number of threads to use [default: 0]";
    };

    sort = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = "Sort results";
    };

    configFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "typos.toml";
      description = "Custom config file";
    };

    isolated = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Ignore implicit configuration files";
    };

    hidden = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Search hidden files and directories";
    };

    noIgnore = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Don't respect ignore files";
    };

    noIgnoreDot = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Don't respect .ignore files";
    };

    noIgnoreGlobal = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Don't respect global ignore files";
    };

    noIgnoreParent = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Don't respect ignore files in parent directories";
    };

    noIgnoreVCS = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Don't respect ignore files in vsc directories";
    };

    binary = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Search binary files";
    };

    noCheckFilenames = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Skip verifying spelling in file names";
    };

    noCheckFiles = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Skip verifying spelling in files";
    };

    noUnicode = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Only allow ASCII characters in identifiers";
    };

    locale = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "en"
          "en-us"
          "en-gb"
          "en-ca"
          "en-au"
        ]
      );
      default = null;
      description = "Language locale to suggest corrections for [possible values: en, en-us, en-gb, en-ca, en-au]";
    };
  };

  config = lib.mkIf cfg.enable {
    settings.linter.typos = {
      options = lib.mkAfter sharedFlags;
      "repair-options" = lib.mkAfter sharedFlags;
    };
  };
}
