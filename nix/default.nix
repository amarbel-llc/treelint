# A pure Nix library that handles the conformist configuration.
#
# Ported from treefmt-nix's default.nix (the formatter half is essentially
# verbatim) and extended with a parallel linter surface: `mkLinterModule` and
# the ./linters modules, which emit `[linter.<name>]` stanzas (RFC 0001 §4).
let
  # The base module configuration that generates and wraps the conformist config
  # with Nix.
  module-options = ./module-options.nix;

  # Program (formatter) to settings mapping.
  programs = import ./programs.nix;

  # Linter to settings mapping. Kept separate from programs so a formatter and
  # a linter MAY share a name (RFC 0001 §4) without the module system merging
  # their option declarations.
  linters = import ./linters.nix;

  # mkFormatterModule builds a module that declares `programs.<name>.*` options
  # and, when enabled, emits a `[formatter.<name>]` stanza. Ported verbatim from
  # treefmt-nix so the ~155 programs/<name>.nix modules port unchanged.
  mkFormatterModule =
    {
      name,
      package ? name,
      mainProgram ? null,
      args ? [ ],
      includes ? [ ],
      excludes ? [ ],
    }:
    {
      pkgs,
      lib,
      config,
      options,
      ...
    }:
    let
      cfg = config.programs.${name};
      opt = options.programs.${name};
    in
    {
      options.programs.${name} = {
        enable = lib.mkEnableOption name;

        package = lib.mkPackageOption pkgs package { };

        includes = lib.mkOption {
          description = "Path / file patterns to include";
          type = lib.types.listOf lib.types.str;
          default = includes;
        };

        excludes = lib.mkOption {
          description = "Path / file patterns to exclude";
          type = lib.types.listOf lib.types.str;
          default = excludes;
        };

        priority = lib.mkOption {
          description = "Priority";
          type = lib.types.nullOr lib.types.int;
          default = null;
        };

        finalPackage = lib.mkOption {
          type = lib.types.package;
          readOnly = true;
          description = "Resulting `${name}` package bundled with plugins, if any.";
        };
      };

      config = lib.mkIf cfg.enable {
        settings.formatter.${name} = {
          command = lib.mkDefault (
            let
              pkg = if opt.finalPackage.isDefined then cfg.finalPackage else cfg.package;
            in
            if mainProgram == null then pkg else "${pkg}/bin/${mainProgram}"
          );
        }
        // (lib.optionalAttrs (args != [ ]) {
          options = if args._type or null == "order" then args else lib.mkBefore args;
        })
        // (lib.optionalAttrs (cfg.includes != [ ]) {
          inherit (cfg) includes;
        })
        // (lib.optionalAttrs (cfg.excludes != [ ]) {
          inherit (cfg) excludes;
        })
        // (lib.optionalAttrs (cfg.priority != null) {
          inherit (cfg) priority;
        });
      };
    };

  # mkLinterModule is the linter analog of mkFormatterModule. It declares
  # `linters.<name>.*` options and, when enabled, emits a `[linter.<name>]`
  # stanza (RFC 0001 §4). Differences from the formatter:
  #   - emits into settings.linter.<name>, not settings.formatter.<name>;
  #   - `command` is the read-only CHECK action;
  #   - adds optional repair-command / repair-options (the autofix action used
  #     in repair mode). The hyphenated TOML keys are quoted because that is the
  #     exact spelling conformist's config struct unmarshals
  #     (config/config.go: toml:"repair-command", toml:"repair-options").
  mkLinterModule =
    {
      name,
      package ? name,
      mainProgram ? null,
      args ? [ ],
      includes ? [ ],
      excludes ? [ ],
      # Default repair command/args, if the tool has a native autofix. A linter
      # with no repair action is a no-op in repair mode (RFC 0001 §4).
      repairMainProgram ? null,
      repairArgs ? [ ],
    }:
    {
      pkgs,
      lib,
      config,
      options,
      ...
    }:
    let
      cfg = config.linters.${name};
      opt = options.linters.${name};
    in
    {
      options.linters.${name} = {
        enable = lib.mkEnableOption name;

        package = lib.mkPackageOption pkgs package { };

        includes = lib.mkOption {
          description = "Path / file patterns to include";
          type = lib.types.listOf lib.types.str;
          default = includes;
        };

        excludes = lib.mkOption {
          description = "Path / file patterns to exclude";
          type = lib.types.listOf lib.types.str;
          default = excludes;
        };

        priority = lib.mkOption {
          description = "Priority";
          type = lib.types.nullOr lib.types.int;
          default = null;
        };

        finalPackage = lib.mkOption {
          type = lib.types.package;
          readOnly = true;
          description = "Resulting `${name}` package bundled with plugins, if any.";
        };
      };

      config = lib.mkIf cfg.enable {
        settings.linter.${name} = {
          command = lib.mkDefault (
            let
              pkg = if opt.finalPackage.isDefined then cfg.finalPackage else cfg.package;
            in
            if mainProgram == null then pkg else "${pkg}/bin/${mainProgram}"
          );
        }
        // (lib.optionalAttrs (args != [ ]) {
          options = if args._type or null == "order" then args else lib.mkBefore args;
        })
        // (lib.optionalAttrs (repairMainProgram != null) {
          "repair-command" = lib.mkDefault (
            let
              pkg = if opt.finalPackage.isDefined then cfg.finalPackage else cfg.package;
            in
            "${pkg}/bin/${repairMainProgram}"
          );
        })
        // (lib.optionalAttrs (repairArgs != [ ]) {
          "repair-options" =
            if repairArgs._type or null == "order" then repairArgs else lib.mkBefore repairArgs;
        })
        // (lib.optionalAttrs (cfg.includes != [ ]) {
          inherit (cfg) includes;
        })
        // (lib.optionalAttrs (cfg.excludes != [ ]) {
          inherit (cfg) excludes;
        })
        // (lib.optionalAttrs (cfg.priority != null) {
          inherit (cfg) priority;
        });
      };
    };

  all-modules =
    nixpkgs:
    [
      {
        _module.args = {
          pkgs = nixpkgs;
          lib = nixpkgs.lib;
        };
      }
      module-options
    ]
    ++ programs.modules
    ++ linters.modules;

  # conformist can be loaded into a submodule. In this case we get our `pkgs` from
  # our own standard option `pkgs`; not externally.
  submodule-modules = [
    (
      { config, lib, ... }:
      let
        inherit (lib)
          mkOption
          types
          ;
      in
      {
        options.pkgs = mkOption {
          type = types.uniq (types.lazyAttrsOf (types.raw or types.unspecified));
          description = ''
            Nixpkgs to use in `conformist`.
          '';
        };
        config._module.args = {
          pkgs = config.pkgs;
        };
      }
    )
    module-options
  ]
  ++ programs.modules
  ++ linters.modules;

  # Use the Nix module system to validate the conformist config file format.
  #
  # nixpkgs is an instance of <nixpkgs>.
  # configuration is an attrset used to configure the nix module.
  evalModule =
    nixpkgs: configuration:
    # NOTE: keep in sync with submoduleWith
    nixpkgs.lib.evalModules {
      modules = all-modules nixpkgs ++ [ configuration ];
      specialArgs = defaultSpecialArgs;
    };

  /**
    The built-in specialArgs for conformist-nix.
    These are module arguments passed to all conformist-nix modules.
  */
  defaultSpecialArgs = {
    inherit mkFormatterModule mkLinterModule;
  };

  /**
    Invoke conformist-nix as a submodule, integrating this into a larger
    configuration management system.

    Unlike in `evalModule`, the caller is responsible for setting
    `_module.args.pkgs` inside the submodule.
  */
  submoduleWith =
    lib:
    {
      modules ? [ ],
      specialArgs ? { },
    }:
    # NOTE: keep in sync with evalModule
    lib.types.submoduleWith {
      modules = submodule-modules ++ modules;
      specialArgs = defaultSpecialArgs // specialArgs;
    };

  # Returns a conformist config file (TOML) generated from the passed
  # configuration.
  mkConfigFile =
    nixpkgs: configuration:
    let
      mod = evalModule nixpkgs configuration;
    in
    mod.config.build.configFile;

  # Returns an instance of conformist, wrapped with some configuration.
  mkWrapper =
    nixpkgs: configuration:
    let
      mod = evalModule nixpkgs configuration;
    in
    mod.config.build.wrapper;
in
{
  inherit
    module-options
    programs
    linters
    all-modules
    submodule-modules
    evalModule
    submoduleWith
    mkConfigFile
    mkWrapper
    ;
}
