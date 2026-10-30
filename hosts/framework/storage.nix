{ config, lib, ... }:
let
  cfg = config.framework.storage;
in
{
  imports = [ ../../modules/zfs-udev-initrd.nix ];
  options.framework.storage = {
    pool = lib.mkOption {
      type = lib.types.str;
      default = "novafs";
    };
    rootDataset = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.pool}/nixos0/root";
    };
    homeDataset = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.pool}/nixos0/data/home";
    };
    tmpDataset = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.pool}/tmp_zfs_home";
    };
    encryptionRoots = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ cfg.pool ];
    };
    nextcloud = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
    espPartuuid = lib.mkOption {
      type = lib.types.str;
      default = "eaa38b89-b406-469c-bbcf-e6be7a43e2e4";
    };
    efiLabel = lib.mkOption {
      type = lib.types.str;
      default = "zbm-rs";
    };
    preferredPoolGuid = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
    portable = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
  };
  config = {
    boot.loader.zbm-rs.enable = true;
    boot.initrd.secrets."/etc/zfs/zroot.key" = "/etc/zfs/zroot.key";
    boot.initrd.systemd.services."zfs-import-${cfg.pool}" = {
      requires = [ "initrd-nixos-copy-secrets.service" ];
      after = [ "initrd-nixos-copy-secrets.service" ];
    };
    boot.zfs.requestEncryptionCredentials = cfg.encryptionRoots;
    boot.initrd.availableKernelModules = lib.optionals cfg.portable [
      "uas"
      "sd_mod"
    ];
    boot.kernelParams = [
      "zswap.enabled=0"
      "zfs.zfs_arc_max=8589934592"
      "efi_pstore.pstore_disable=0"
    ];

    fileSystems."/" = {
      device = cfg.rootDataset;
      fsType = "zfs";
      options = [ "zfsutil" ];
    };
    fileSystems."/home/okhsunrog/Nextcloud" = lib.mkIf cfg.nextcloud {
      device = "${cfg.pool}/nextcloud";
      fsType = "zfs";
      options = [ "zfsutil" ];
    };
    fileSystems."/home/okhsunrog/tmp_zfs" = {
      device = cfg.tmpDataset;
      fsType = "zfs";
      options = [ "zfsutil" ];
    };
  };
}
