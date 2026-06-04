# jsonnet-lint as a conformist LINTER (RFC 0001 §4). It reports problems in
# Jsonnet source and exits non-zero on findings; no autofix, so check-only (a
# no-op in repair mode). Reclassified from a treefmt-nix "formatter"
# (conformist#6). The binary (jsonnet-lint) differs from the package name
# (go-jsonnet), so mainProgram is set explicitly.
{
  mkLinterModule,
  ...
}:
{
  meta.maintainers = [ ];

  imports = [
    (mkLinterModule {
      name = "jsonnet-lint";
      package = "go-jsonnet";
      mainProgram = "jsonnet-lint";
      includes = [
        "*.jsonnet"
        "*.libsonnet"
      ];
    })
  ];
}
