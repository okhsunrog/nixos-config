{ ... }:
{
  boot.loader.zbm-rs.enable = true;
  boot.initrd.secrets."/etc/zfs/zroot.key" = "/etc/zfs/zroot.key";
  boot.initrd.systemd.services.zfs-import-novafs = {
    requires = [ "initrd-nixos-copy-secrets.service" ];
    after = [ "initrd-nixos-copy-secrets.service" ];
  };
  boot.zfs.requestEncryptionCredentials = [ "novafs" ];
  boot.kernelParams = [
    "zswap.enabled=0"
    "zfs.zfs_arc_max=8589934592"
    "efi_pstore.pstore_disable=0"
  ];

  fileSystems."/" = {
    device = "novafs/nixos0/root";
    fsType = "zfs";
    options = [ "zfsutil" ];
  };
  fileSystems."/home" = {
    device = "novafs/nixos0/data/home";
    fsType = "zfs";
    options = [ "zfsutil" ];
    # Account activation creates home directories before switch-root.
    neededForBoot = true;
  };
  fileSystems."/home/okhsunrog/Nextcloud" = {
    device = "novafs/nextcloud";
    fsType = "zfs";
    options = [ "zfsutil" ];
  };
  fileSystems."/home/okhsunrog/tmp_zfs" = {
    device = "novafs/tmp_zfs_home";
    fsType = "zfs";
    options = [ "zfsutil" ];
  };

}
