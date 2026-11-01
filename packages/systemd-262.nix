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
    patches = lib.unique (
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
        )
      ++ [ ./systemd-s2h-timer.patch ]
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
assert lib.assertMsg (pkgs.systemd.version == "261.3")
  "systemd-262.nix expects systemd 261.3 as its base. Recheck the local patches and overrideAttrs adapter, or replace this package with the tested upstream systemd.";
wrap (
  pkgs.systemd.overrideAttrs (
    previous:
    adapt previous
    // {
      # Exercise real timerfds, including the early-wake skews measured on the
      # Framework. Run the focused test even though the full upstream suite is
      # unsuitable for this package build sandbox.
      postBuild = (previous.postBuild or "") + ''
        ninja test-sleep-timer
        ./test-sleep-timer
      '';
    }
  )
)
