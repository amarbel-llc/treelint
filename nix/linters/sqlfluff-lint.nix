# sqlfluff-lint as a conformist LINTER (RFC 0001 §4). `sqlfluff lint` reports
# SQL style/parse problems and exits non-zero on findings; check-only here (a
# no-op in repair mode). The autofix path (`sqlfluff fix`) is provided by the
# separate `sqlfluff` FORMATTER (nix/programs/sqlfluff.nix), so this linter does
# not wire a repair-command. Reclassified from a treefmt-nix "formatter"
# (conformist#6).
#
# The `--dialect` flag is shared with the sqlfluff formatter, so it is read from
# `programs.sqlfluff.dialect` (the formatter module owns that option). Reading it
# does not force the formatter to be enabled.
{
  lib,
  config,
  mkLinterModule,
  ...
}:
let
  cfg = config.linters.sqlfluff-lint;
  dialect = config.programs.sqlfluff.dialect or null;
in
{
  meta.maintainers = [ ];

  imports = [
    (mkLinterModule {
      name = "sqlfluff-lint";
      package = "sqlfluff";
      mainProgram = "sqlfluff";
      args = [
        "lint"
        "--disable-progress-bar"
        "--processes"
        "0"
      ];
      includes = [ "*.sql" ];
    })
  ];

  config = lib.mkIf cfg.enable {
    settings.linter.sqlfluff-lint = lib.mkIf (dialect != null) {
      options = lib.mkAfter [ "--dialect=${dialect}" ];
    };
  };
}
