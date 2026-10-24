{ lib, pkgs, ... }:
{
  programs.niri.enable = true;
  programs.niri.useNautilus = false;
  programs.xwayland.enable = true;
  # Keep the cloned Plasma wallet as the provider for existing application keys.
  # greetd delegates its auth and session stacks to PAM login.
  services.gnome.gnome-keyring.enable = lib.mkForce false;
  security.pam.services.login.kwallet = {
    enable = true;
    forceRun = true;
  };
  services.dbus.packages = [ pkgs.kdePackages.kwallet ];
  systemd.packages = [ pkgs.kdePackages.kwallet-pam ];
  systemd.user.services.plasma-kwallet-pam.wantedBy = [ "graphical-session.target" ];
  systemd.user.services.niri-secret-service = {
    description = "KWallet Secret Service for the Niri session";
    partOf = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    after = [ "plasma-kwallet-pam.service" ];
    serviceConfig.ExecStart = "${pkgs.kdePackages.kwallet}/bin/ksecretd";
  };
  xdg.portal.extraPortals = [ pkgs.kdePackages.kwallet ];
  xdg.portal.config.niri."org.freedesktop.impl.portal.Secret" = lib.mkForce "kwallet";
  services.greetd = {
    enable = true;
    settings.default_session.command = "${pkgs.tuigreet}/bin/tuigreet --cmd niri-session";
  };
  environment.systemPackages = with pkgs; [
    kdePackages.kwalletmanager
    foot
    fuzzel
    waybar
    mako
    swaylock
    xwayland-satellite
  ];
  environment.etc."niri/config.kdl".text = ''
    input {
      keyboard {
        xkb {
          layout "us,ru"
          options "grp:caps_toggle"
        }
      }
      touchpad { tap; natural-scroll; }
    }
    spawn-at-startup "waybar"
    spawn-at-startup "mako"
    binds {
      Mod+Return { spawn "foot"; }
      Mod+D { spawn "fuzzel"; }
      Mod+Q { close-window; }
      Mod+Left { focus-column-left; }
      Mod+Right { focus-column-right; }
      Mod+Up { focus-window-up; }
      Mod+Down { focus-window-down; }
      Mod+Shift+Left { move-column-left; }
      Mod+Shift+Right { move-column-right; }
      Mod+Page_Down { focus-workspace-down; }
      Mod+Page_Up { focus-workspace-up; }
      Mod+Shift+E { quit; }
      Mod+Shift+Slash { show-hotkey-overlay; }
      Mod+L { spawn "swaylock"; }
    }
  '';
}
