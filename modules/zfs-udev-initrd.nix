{ pkgs, ... }:
{
  # ZFS udev rules use the host package set's absolute modprobe path. A
  # separately pinned initrd systemd may bring a different kmod, so include
  # the exact callout too, with its symlink target and runtime dependencies.
  boot.initrd.systemd.storePaths = [ "${pkgs.kmod}/bin/modprobe" ];
}
