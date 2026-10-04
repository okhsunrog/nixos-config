{ pkgs, ... }:
{
  imports = [ ./hardware.nix ];

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

  boot.loader.zfsbootmenu = {
    enable = true;
    rootDataset = "novafs/nixos0/root";
    keyFile = "/etc/zfs/zroot.key";
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

  programs.niri.enable = true;
  systemd.user.services.polkit-agent = {
    description = "Polkit authentication agent";
    wantedBy = [ "niri.service" ];
    after = [ "niri.service" ];
    partOf = [ "niri.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
      Restart = "on-failure";
    };
  };
  services.greetd = {
    enable = true;
    settings.default_session.command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd niri-session";
  };
  environment.etc."niri/config.kdl".source = ./niri.kdl;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };
  security.rtkit.enable = true;
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;
  users.users.okhsunrog = {
    isNormalUser = true;
    uid = 1000;
    group = "okhsunrog";
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
    ];
    # Supplied outside Git during installation; account stays locked if absent.
    hashedPasswordFile = "/etc/nixos/secrets/okhsunrog-password-hash";
  };
  users.groups.okhsunrog.gid = 1000;
  users.users.root.hashedPasswordFile = "/etc/nixos/secrets/root-password-hash";
  zramSwap.enable = true;
  zramSwap.memoryPercent = 25;
  environment.systemPackages = with pkgs; [
    git
    vim
    firefox
    foot
    fuzzel
    waybar
    mako
    swaybg
    swaylock
    wl-clipboard
    brightnessctl
    playerctl
    pavucontrol
    nautilus
    xwayland-satellite
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
