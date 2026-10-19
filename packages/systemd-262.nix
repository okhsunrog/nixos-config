{
  pkgs,
  lib ? pkgs.lib,
}:
let
  source = pkgs.fetchFromGitHub {
    owner = "systemd";
    repo = "systemd";
    tag = "v262.1";
    hash = "sha256-BE94QT8jd0lTp8u/ZCi2KraeiuXJeJhnwgPhmFYKUew=";
  };
  adapt = previous: {
    version = "262.1";
    src = source;
    # Match Nixpkgs' 262 patch set: rootprefix and the timesyncd fix are
    # upstream, and the timezone patch needs its 262 rebase.
    patches =
      map
        (
          patch:
          if lib.hasSuffix "0002-Change-usr-share-zoneinfo-to-etc-zoneinfo.patch" (toString patch) then
            ./systemd-zoneinfo-262.patch
          else if lib.hasSuffix "0005-core-don-t-taint-on-unmerged-usr.patch" (toString patch) then
            ./systemd-taint-262.patch
          else
            patch
        )
        (
          builtins.filter (
            patch:
            !(builtins.any (suffix: lib.hasSuffix suffix (toString patch)) [
              "-postpone-d-bus-queue-dispatch.patch"
              "0003-add-rootprefix-to-lookup-dir-paths.patch"
              "0006-timesyncd-disable-NSCD-when-DNSSEC-validation-is-dis.patch"
            ])
          ) previous.patches
        );
    mesonFlags = builtins.filter (flag: !(lib.hasPrefix "-Dgcrypt=" flag)) previous.mesonFlags;
  };
  # Preserve NixOS's package options and patches when the system module
  # overrides the package. The old module adds a backport already in 262.
  wrap =
    package:
    package
    // {
      overrideAttrs =
        override:
        wrap (
          package.overrideAttrs (
            previous:
            let
              adjusted = override previous;
            in
            adjusted // adapt (previous // adjusted)
          )
        );
    };
in
wrap (pkgs.systemd.overrideAttrs adapt)
