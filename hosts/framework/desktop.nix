{ pkgs, ... }:
{
  services.desktopManager.plasma6.enable = true;
  services.displayManager.plasma-login-manager.enable = true;
  services.displayManager.defaultSession = "plasma";
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };
  security.rtkit.enable = true;
  hardware.bluetooth.enable = true;
  services.xserver.xkb = {
    layout = "us,ru";
    options = "grp:caps_toggle,terminate:ctrl_alt_bksp";
  };
  environment.systemPackages = with pkgs; [
    kdePackages.konsole
    kdePackages.dolphin
  ];
}
