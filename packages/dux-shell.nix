{ pkgs, dux-shell }:
(dux-shell.lib.mkDmsShell pkgs).overrideAttrs (old: {
  postInstall = (old.postInstall or "") + ''
    patch -d "$out/share/quickshell/dms" -p1 < ${./patches/dux-session-cursor.patch}
  '';
})
