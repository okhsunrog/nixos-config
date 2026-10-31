{ pkgs, dux-shell }:
(dux-shell.lib.mkDmsShell pkgs).overrideAttrs (old: {
  postPatch = (old.postPatch or "") + ''
    patch -p1 < ${./patches/dux-gtk-theme-prefix-core.patch}
  '';
  postInstall = (old.postInstall or "") + ''
    patch -d "$out/share/quickshell/dms" -p1 < ${./patches/dux-session-cursor.patch}
    patch -d "$out/share/quickshell/dms" -p1 < ${./patches/dux-gtk-theme-directory.patch}
  '';
})
