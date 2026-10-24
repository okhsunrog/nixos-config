{
  config,
  lib,
  pkgs,
  dux-shell,
  dux-calendar,
  dux-files,
  dux-search,
  dux-gop,
  ...
}:
let
  templates = "${dux-shell}/core/internal/config/embedded";
  baseConfig =
    builtins.replaceStrings
      [ "// layout \"us,ru\"" "// options \"grp:win_space_toggle,compose:ralt,ctrl:nocaps\"" ]
      [ "layout \"us,ru\"" "options \"grp:caps_toggle\"" ]
      (builtins.readFile "${templates}/niri.kdl");
  defaults = lib.genAttrs [ "colors" "layout" "alttab" "binds" "input" ] (
    name:
    pkgs.writeText "niri-dms-${name}.kdl" (
      builtins.replaceStrings [ "{{TERMINAL_COMMAND}}" ] [ "rio" ] (
        builtins.readFile "${templates}/niri-${name}.kdl"
      )
    )
  );
in
{
  imports = [
    dux-shell.homeModules.default
    dux-calendar.homeModules.default
    dux-files.homeModules.default
    dux-search.homeModules.default
  ];
  home.username = "okhsunrog";
  home.homeDirectory = "/home/okhsunrog";
  home.stateVersion = "26.05";
  programs.home-manager.enable = true;
  home.sessionVariables.TERMINAL = "rio";
  home.pointerCursor = {
    package = pkgs.bibata-cursors;
    name = "Bibata-Modern-Ice";
    size = 24;
  };
  home.packages = [ dux-gop.packages.${pkgs.stdenv.hostPlatform.system}.default ];
  programs.dank-material-shell = {
    enable = true;
    systemd.enable = true;
    enableSystemMonitoring = true;
    enableVPN = true;
    enableDynamicTheming = true;
    enableAudioWavelength = true;
    # Events are supplied by Dux Calendar; omit the legacy khal backend.
    enableCalendarEvents = false;
    # GUI settings and session state remain writable in the isolated home.
  };
  programs.dank-calendar = {
    enable = true;
    systemd.enable = true;
  };
  programs.dux-files = {
    enable = true;
    systemd.enable = true;
  };
  programs.dsearch.enable = true;
  systemd.user.services.dsearch = {
    Unit.PartOf = [ "graphical-session.target" ];
    Install.WantedBy = lib.mkForce [ "graphical-session.target" ];
  };
  xdg.enable = true;
  # Update only the folder association; keep browser and all other MIME choices.
  home.activation.duxFileManager = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${pkgs.crudini}/bin/crudini --set "$HOME/.config/mimeapps.list" \
      'Default Applications' inode/directory 'dev.duxlabs.files.desktop;'
  '';
  xdg.configFile."xdg-terminals.list".text = "rio.desktop\n";
  xdg.configFile."niri/config.kdl".text = baseConfig;
  # DMS edits its own generated includes. Seed them once, without making them
  # immutable or replacing user changes on subsequent rebuilds.
  home.activation.duxNiriDefaults = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${lib.concatMapStringsSep "\n" (name: ''
      if [ ! -e "$HOME/.config/niri/dms/${name}.kdl" ]; then
        run ${pkgs.coreutils}/bin/install -D -m 0644 ${defaults.${name}} "$HOME/.config/niri/dms/${name}.kdl"
      fi
    '') (lib.attrNames defaults)}
  '';
}
