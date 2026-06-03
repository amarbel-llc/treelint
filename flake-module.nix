# flake-parts module for conformist. Ported from treefmt-nix's flake-module.nix.
#
# Exposes `perSystem.conformist`, a submodule carrying the full conformist settings
# surface (formatters + linters). By default it wires `formatter.<system>` (for
# `nix fmt`) and `checks.<system>.conformist` (a read-only `conformist check` gate).
#
# Note: conformist is not in nixpkgs, so the module's `package` option has no
# default — a consumer MUST set `conformist.package` (e.g. to the conformist flake's
# package output for the current system).
{
  self,
  lib,
  flake-parts-lib,
  ...
}:
let
  inherit (flake-parts-lib)
    mkPerSystemOption
    ;
  inherit (lib)
    mkOption
    types
    ;
  conformist-lib = import ./nix;
in
{
  options = {
    perSystem = mkPerSystemOption (
      {
        config,
        pkgs,
        ...
      }:
      {
        options.conformist = mkOption {
          description = ''
            Project-level conformist configuration.

            Use `config.conformist.build.wrapper` to get the resulting conformist
            package based on this configuration.

            By default conformist will set the `formatter.<system>` attribute of
            the flake (used by `nix fmt`) and a `checks.<system>.conformist`
            read-only gate.

            You MUST set `config.conformist.package` — conformist is not in nixpkgs.
          '';
          type = conformist-lib.submoduleWith lib {
            modules = [
              {
                options.pkgs = lib.mkOption {
                  default = pkgs;
                  defaultText = lib.literalMD "`pkgs` (module argument of `perSystem`)";
                };
                options.flakeFormatter = lib.mkOption {
                  type = types.bool;
                  default = true;
                  description = ''
                    Enables `conformist` as the default formatter used by `nix fmt`.
                  '';
                };
                options.flakeCheck = lib.mkOption {
                  type = types.bool;
                  default = true;
                  description = ''
                    Add a flake check to run `conformist check`.
                  '';
                };
                options.projectRoot = lib.mkOption {
                  type = types.path;
                  default = self;
                  defaultText = lib.literalExpression "self";
                  description = ''
                    Path to the root of the project on which conformist operates.
                  '';
                };

                config.projectRootFile = lib.mkDefault "flake.nix";
              }
            ];
          };
          default = { };
        };
        config = {
          checks = lib.mkIf config.conformist.flakeCheck {
            conformist = config.conformist.build.check config.conformist.projectRoot;
          };
          formatter = lib.mkIf config.conformist.flakeFormatter (
            lib.mkDefault config.conformist.build.wrapper
          );
        };
      }
    );
  };
}
