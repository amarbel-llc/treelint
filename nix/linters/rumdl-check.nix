# rumdl-check as a conformist LINTER (RFC 0001 §4). The check action is
# `rumdl check` (read-only, exits non-zero on findings); the repair action is
# `rumdl check --fix` (autofix in repair mode). treefmt-nix shipped this as a
# "formatter" that always ran `check --fix`; conformist splits the two
# (conformist#6).
{
  mkLinterModule,
  ...
}:
{
  meta.maintainers = [ "delafthi" ];

  imports = [
    (mkLinterModule {
      name = "rumdl-check";
      package = "rumdl";
      mainProgram = "rumdl";
      args = [ "check" ];
      repairArgs = [
        "check"
        "--fix"
      ];
      includes = [ "*.md" ];
    })
  ];
}
