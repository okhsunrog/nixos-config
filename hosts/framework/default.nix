{ pkgs, ... }:
{
  imports = [
    ./hardware.nix
    ./secureboot.nix
    ./daily-tools.nix
    ./secrets.nix
    ./corporate.nix
  ];

  networking.hostName = "nova-nixos";
  networking.hostId = "00bab10c";
  networking.networkmanager.enable = true;
  time.timeZone = "Europe/Moscow";
  i18n.defaultLocale = "en_US.UTF-8";
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
