{ config, ... }:
{
  imports = [ ../../modules/framework-environments ];
  framework.environments = {
    enable = true;
    user = "okhsunrog";
    uid = 1000;
    gid = 1000;
    homeMode = "shared";
    configProfiles = {
      enable = true;
      mutableFiles = [
        ".config/gtk-3.0/gtk.css"
        ".config/gtk-3.0/settings.ini"
        ".config/gtk-4.0/gtk.css"
        ".config/gtk-4.0/settings.ini"
      ];
      dconfKeys = map (key: "/org/gnome/desktop/interface/${key}") [
        "gtk-theme"
        "color-scheme"
        "icon-theme"
        "cursor-theme"
        "cursor-size"
        "accent-color"
      ];
    };
    entries = {
      kde = {
        dataset = config.framework.storage.homeDataset;
        backup = "mira";
      };
      niri = {
        # Ordinary application state is shared; only declared desktop exceptions differ.
        enable = true;
        dataset = config.framework.storage.homeDataset;
        backup = "mira";
      };
    };
    variants.niri = ./desktops/niri.nix;
  };
}
