{ pkgs, ... }:
{
  imports = [
    ./hardware.nix
    ./secureboot.nix
    ./daily-tools.nix
    ./personal-packages.nix
    ./arctern.nix
    ./ayugram-plengine.nix
    ./secrets.nix
    ./corporate.nix
    ./floppa.nix
    ../../modules/novpn
  ];

  services.novpn = {
    enable = true;
    user = "okhsunrog";
  };

  networking.hostName = "nova-nixos";
  networking.hostId = "00bab10c";
  networking.networkmanager.enable = true;
  time.timeZone = "Europe/Moscow";
  i18n.defaultLocale = "en_US.UTF-8";
  # Plasma's migrated per-user format settings use British English.
  i18n.supportedLocales = [
    "en_US.UTF-8/UTF-8"
    "en_GB.UTF-8/UTF-8"
    "ru_RU.UTF-8/UTF-8"
  ];
  security.sudo.extraRules = [
    {
      users = [ "okhsunrog" ];
      commands = [
        {
          command = "ALL";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];
  services.xserver.xkb = {
    layout = "us,ru";
    options = "grp:caps_toggle,terminate:ctrl_alt_bksp";
  };
  console.keyMap = "ru";

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
    "mem_sleep_default=deep"
    "acpi_osi=\"!Windows 2020\""
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

  services.desktopManager.plasma6.enable = true;
  services.displayManager.plasma-login-manager.enable = true;
  services.displayManager.defaultSession = "plasma";
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };
  security.rtkit.enable = true;
  hardware.bluetooth.enable = true;
  users.users.okhsunrog = {
    isNormalUser = true;
    uid = 1000;
    group = "okhsunrog";
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
    ];
  };
  users.groups.okhsunrog.gid = 1000;
  zramSwap.enable = true;
  zramSwap.memoryPercent = 25;
  environment.systemPackages = with pkgs; [
    kdePackages.konsole
    kdePackages.dolphin
    git
  ];
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  system.stateVersion = "26.05";
}
