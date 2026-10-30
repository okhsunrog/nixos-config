{ ... }:
{
  # Keep Plasma and application preferences writable; do not redeclare them here.
  xdg.configFile."kde-mimeapps.list".text = ''
    [Default Applications]
    inode/directory=org.kde.dolphin.desktop;
  '';
}
