{ pkgs, ayugram-plengine, ... }:
let
  packages = ayugram-plengine.packages.${pkgs.stdenv.hostPlatform.system};
  plugins = packages.plengine-plugins;
in
{
  nixpkgs.overlays = [
    (_final: _previous: { ayugram-desktop = packages.default; })
  ];
  environment.systemPackages = [ plugins ];
  home-manager.users.okhsunrog.systemd.user.tmpfiles.rules = [
    "d %h/.local/share/AyuGramDesktop/plugins 0700 - - -"
    "L+ %h/.local/share/AyuGramDesktop/plugins/ayu-plengine-channel-reader.so - - - - ${plugins}/lib/ayugram/plugins/ayu-plengine-channel-reader.so"
    "L+ %h/.local/share/AyuGramDesktop/plugins/ayu-plengine-smoke-plugin.so - - - - ${plugins}/lib/ayugram/plugins/ayu-plengine-smoke-plugin.so"
  ];
}
