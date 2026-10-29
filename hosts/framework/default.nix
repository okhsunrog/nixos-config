{ pkgs, ... }:
{
  imports = [
    ./hardware.nix
    ./storage.nix
    ./environments.nix
    ./home-manager.nix
    ./desktop.nix
    ./virtualisation.nix
    ./secureboot.nix
    ./efi.nix
    ./daily-tools.nix
    ./personal-packages.nix
    ./arctern.nix
    ./ayugram-plengine.nix
    ./peripherals.nix
    ./power.nix
    ./secrets.nix
    ./corporate.nix
    ./webkit.nix
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
  # Keep Arch's Wi-Fi profile bindings valid for this built-in adapter.
  systemd.network.links."10-framework-wifi" = {
    matchConfig.PermanentMACAddress = "8c:f8:c5:74:b2:56";
    linkConfig = {
      NamePolicy = "";
      Name = "wlan0";
    };
  };
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
  console.keyMap = "ru";

  programs.bash.interactiveShellInit = ''
    if (( EUID == 0 )); then
      HISTSIZE=100000
      HISTFILESIZE=200000
      shopt -s histappend
    fi
  '';
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };
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
