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
      default = [
        cfg.pool
        cfg.rootDataset
        cfg.homeDataset
        "${cfg.pool}/nextcloud"
        cfg.tmpDataset
      ];
    };
    nextcloud = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
    espPartuuid = lib.mkOption {
      type = lib.types.str;
      default = "aafa93cb-dbf2-483c-8ca2-cb035104f8b9";
    };
    efiLabel = lib.mkOption {
      type = lib.types.str;
      default = "zbm-rs";
    };
    preferredPoolGuid = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "13099373940756918353";
    };
    swapLuksUuid = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "965b36af-dc40-4e5d-aa7b-49f49407c3ef";
    };
    swapPartuuid = lib.mkOption {
      type = lib.types.str;
      default = "08e3880a-963d-4b43-9b9d-65bd955c153c";
      description = "Physical LUKS swap partition identity, independent of its decrypted swap UUID.";
    };
    portable = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
  };
  config = {
    boot.loader.zbm-rs.enable = true;
    # Declare topology independently of activation: rescue must retain the same
    # cancellation guard even if the main system's hibernation is disabled.
    boot.loader.zbm-rs.hibernation = lib.mkIf (cfg.swapLuksUuid != null) {
      enable = !cfg.portable;
      swap = {
        type = "luks2";
        partuuid = cfg.swapPartuuid;
        luksDevice = "nvme-swap";
      };
      credential = {
        type = "zfs-unlock";
        poolGuid = cfg.preferredPoolGuid;
        encryptionRoot = cfg.rootDataset;
      };
    };
    boot.initrd.secrets."/etc/zfs/zroot.key" = "/etc/zfs/zroot.key";
    boot.initrd.systemd.services."zfs-import-${cfg.pool}" = {
      requires = [ "initrd-nixos-copy-secrets.service" ];
      after = [ "initrd-nixos-copy-secrets.service" ];
    };
    boot.zfs.requestEncryptionCredentials = cfg.encryptionRoots;
    boot.initrd.luks.devices = lib.optionalAttrs (cfg.swapLuksUuid != null) {
      nvme-swap = {
        device = "/dev/disk/by-uuid/${cfg.swapLuksUuid}";
        keyFile = "/etc/zfs/zroot.key";
      };
    };
    boot.initrd.systemd.services."systemd-cryptsetup@nvme\\x2dswap" =
      lib.mkIf (cfg.swapLuksUuid != null)
        {
          overrideStrategy = "asDropin";
          requires = [ "initrd-nixos-copy-secrets.service" ];
          after = [ "initrd-nixos-copy-secrets.service" ];
        };
    swapDevices = lib.optionals (cfg.swapLuksUuid != null) [
      { device = "/dev/mapper/nvme-swap"; }
    ];
    # The internal installation uses the VM-validated protected path. Portable
    # repair systems retain ordinary paging without enabling hibernation.
    boot.zfs.unsafeAllowHibernation = config.boot.loader.zbm-rs.hibernation.enable;
    systemd.sleep.settings.Sleep = lib.mkIf (cfg.swapLuksUuid != null) {
      AllowHibernation = config.boot.loader.zbm-rs.hibernation.enable;
      AllowHybridSleep = false;
      AllowSuspendThenHibernate = false;
    };
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
