# Enumerate the formatter program modules under ./programs.
#
# Ported from treefmt-nix's programs.nix. Each entry maps 1:1 to a
# programs/<name>.nix module that, when its `programs.<name>.enable` is set,
# emits a `[formatter.<name>]` stanza into the generated conformist config.
let
  # All the directory entries. We assume they are all files.
  files = builtins.attrNames (builtins.readDir ./programs);

  filenameToPath = filename: ./programs + "/${filename}";

  removeNixExt = filename: builtins.substring 0 (builtins.stringLength filename - 4) filename;
in
{
  # The list of program names. Maps 1:1 with the filename.
  names = map removeNixExt files;

  # The module filenames.
  modules = map filenameToPath files;
}
