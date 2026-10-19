# OrcaSlicer

`hosts/framework/personal-packages.nix` installs the pinned nixpkgs OrcaSlicer
package (2.4.2 at migration), with its native desktop entry
`com.orcaslicer.OrcaSlicer.desktop`.

The Arch desktop entry pointed directly to a local Ubuntu AppImage. Its AppRun
script uses `#!/bin/bash`, which is absent on NixOS, causing the AppImage runtime
to exit with `execv error: No such file or directory`. The native package avoids
that dependency on host FHS paths.

On this Intel Core Ultra/KWin setup, the native package's WebKit Home page was
blank. A launch with `WEBKIT_DISABLE_DMABUF_RENDERER=1` rendered it successfully;
switching to X11 alone did not. A small package wrapper sets this variable only
for OrcaSlicer. It reuses the cached native package without rebuilding C++ or
changing the system-wide graphics environment.

The old user desktop entry was moved out of `~/.local/share/applications`, and
MIME associations were changed from `orca-slicer.desktop` to the native desktop
ID. Existing `~/.config/OrcaSlicer` settings and profiles were retained. The old
AppImages remain in `~/Applications`; the menu uses the Nix package.

Migration backups are in
`~/tmp_zfs/codex_tmp/orcaslicer-launch-20261019/`.
