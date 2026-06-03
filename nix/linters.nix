# Enumerate the linter modules under ./linters.
#
# Parallel to programs.nix, but for conformist's `[linter.<name>]` surface
# (RFC 0001 §4). Each entry maps 1:1 to a linters/<name>.nix module that, when
# its `linters.<name>.enable` is set, emits a `[linter.<name>]` stanza into the
# generated conformist config. Kept in a separate namespace from programs so a
# linter and a formatter MAY share a name without the module system merging them
# (RFC 0001 §4: "A linter name MAY collide with a formatter name; the two are
# independent tools").
let
  files = builtins.attrNames (builtins.readDir ./linters);

  filenameToPath = filename: ./linters + "/${filename}";

  removeNixExt = filename: builtins.substring 0 (builtins.stringLength filename - 4) filename;
in
{
  # The list of linter names. Maps 1:1 with the filename.
  names = map removeNixExt files;

  # The module filenames.
  modules = map filenameToPath files;
}
