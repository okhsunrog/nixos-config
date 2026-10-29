{
  config,
  lib,
  pkgs,
  dux-greeter,
  dux-files,
  ...
}:
{
  imports = [
    dux-greeter.nixosModules.default
    dux-files.nixosModules.default
  ];
  programs.niri.enable = true;
  programs.niri.useNautilus = false;
  programs.xwayland.enable = true;
  services.displayManager.defaultSession = "niri";
  programs.dms-greeter = {
    enable = true;
    compositor.name = "niri";
    configHome = "/home/okhsunrog";
    logs = {
      save = true;
      path = "/var/lib/dms-greeter/greeter.log";
    };
  };
  # Dux Greeter uses greetd's PAM service. Override its auth substack rather
  # than the generic login stack, which is also used by console logins.
  security.pam.services = {
    greetd.rules.auth.login.modulePath = lib.mkForce "greetd-password";
    greetd-password = {
      fprintAuth = false;
      allowNullPassword = false;
    };
    # Dux Shell runs its own fingerprint PAM context alongside this password
    # context, so either method can unlock without blocking the other.
    dankshell = {
      fprintAuth = false;
      allowNullPassword = false;
    };
  };
  home-manager.users.okhsunrog = import ../home/niri.nix;
  programs.dux-files = {
    enable = true;
    # The Home Manager module owns the single session service.
    systemd.enable = false;
    portal = {
      enable = true;
      preferred = true;
      desktop = "niri";
    };
  };
  xdg.portal.config.niri."org.freedesktop.impl.portal.FileChooser" = lib.mkForce "dfiles";
  # Preserve the user's existing passwordless wallet and application keys.
  services.gnome.gnome-keyring.enable = lib.mkForce false;
  services.dbus.packages = [ pkgs.kdePackages.kwallet ];
  systemd.user.services.niri-secret-service = {
    description = "KWallet Secret Service for the Niri session";
    partOf = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig.ExecStart = "${pkgs.kdePackages.kwallet}/bin/ksecretd";
  };
  xdg.portal.extraPortals = [ pkgs.kdePackages.kwallet ];
  xdg.portal.config.niri."org.freedesktop.impl.portal.Secret" = lib.mkForce "kwallet";
  services.udisks2.enable = true;
  services.gvfs.enable = true;
  services.accounts-daemon.enable = true;
  security.polkit.enable = true;
  # TuneD already provides the power-profiles D-Bus API and UPower on this host.
  environment.systemPackages = [
    pkgs.kdePackages.kwalletmanager
    pkgs.xwayland-satellite
  ];
}
