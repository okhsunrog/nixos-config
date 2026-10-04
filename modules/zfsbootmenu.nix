{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.boot.loader.zfsbootmenu;
  pool = builtins.head (lib.splitString "/" cfg.rootDataset);
  rootGenerator = pkgs.replaceVarsWith {
    src = ./zbm-root-generator.sh;
    isExecutable = true;
    replacements = {
      bash = "${pkgs.bash}/bin/bash";
      path = lib.makeBinPath [ pkgs.coreutils ];
      inherit pool;
    };
  };
  publisher = pkgs.replaceVarsWith {
    src = ./publish-boot.sh;
    isExecutable = true;
    replacements = {
      bash = "${pkgs.bash}/bin/bash";
      path = lib.makeBinPath [
        pkgs.coreutils
        pkgs.util-linux
        pkgs.gawk
        pkgs.jq
        config.boot.zfs.package
      ];
      inherit pool;
      hostId = config.networking.hostId;
    };
  };
in
{
  options.boot.loader.zfsbootmenu = {
    enable = lib.mkEnableOption "booting through an existing ZFSBootMenu";
    rootDataset = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Initial root dataset. ZBM can select a snapshot clone in the same pool.";
    };
    keyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Runtime path to a ZFS key file, appended to the published initrd outside the Nix store.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = builtins.match "[A-Za-z][A-Za-z0-9_.:-]*/[A-Za-z0-9_./:-]+" cfg.rootDataset != null;
        message = "ZFSBootMenu requires a pool/dataset rootDataset.";
      }
      {
        assertion = config.fileSystems."/".device == cfg.rootDataset;
        message = "ZFSBootMenu rootDataset must match fileSystems.\"/\".device.";
      }
      {
        assertion = !(config.fileSystems ? "/nix");
        message = "Keep /nix inside the root dataset for self-contained ZBM snapshots.";
      }
    ];
    boot.supportedFilesystems = [ "zfs" ];
    boot.zfs.devNodes = lib.mkDefault "/dev/disk/by-id";
    boot.zfs.forceImportRoot = false;
    boot.initrd.systemd.enable = true;
    boot.initrd.systemd.root = null;
    boot.initrd.systemd.contents."/etc/systemd/system-generators/zbm-root-generator".source =
      rootGenerator;
    boot.loader.grub.enable = false;
    boot.loader.systemd-boot.enable = false;
    boot.loader.efi.canTouchEfiVariables = false;
    boot.loader.external = {
      enable = true;
      installHook = publisher;
    };
    boot.loader.supportsInitrdSecrets = true;
    boot.initrd.secrets = lib.mkIf (cfg.keyFile != null) {
      "${cfg.keyFile}" = cfg.keyFile;
    };
    boot.initrd.systemd.services."zfs-import-${pool}" = lib.mkIf (cfg.keyFile != null) {
      requires = [ "initrd-nixos-copy-secrets.service" ];
      after = [ "initrd-nixos-copy-secrets.service" ];
    };
    boot.bootspec.enable = true;
    # Explicit fileSystems mounts only: never bulk-mount another BE's data.
    systemd.services.zfs-mount.enable = false;
    systemd.services.zfs-share.enable = false;
  };
}
