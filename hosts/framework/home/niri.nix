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
      [
        "// layout \"us,ru\""
        "// options \"grp:win_space_toggle,compose:ralt,ctrl:nocaps\""
        "environment {"
      ]
      [
        "layout \"us,ru\""
        "options \"grp:caps_toggle\""
        ''
          environment {
            QT_QPA_PLATFORMTHEME "gtk3"
            QT_QPA_PLATFORMTHEME_QT6 "gtk3"
        ''
      ]
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
  home.sessionVariables = {
    TERMINAL = "rio";
    QT_QPA_PLATFORMTHEME = "gtk3";
    QT_QPA_PLATFORMTHEME_QT6 = "gtk3";
  };
  home.pointerCursor = {
    package = pkgs.bibata-cursors;
    name = "Bibata-Modern-Ice";
    size = 24;
  };
  home.packages = [
    dux-gop.packages.${pkgs.stdenv.hostPlatform.system}.default
    pkgs.adw-gtk3
  ];
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
  # Keep the settings file writable while pinning the authentication policy.
  # Other preferences remain editable through the Dux UI.
  home.activation.duxLockAuth = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${
      lib.getExe (
        pkgs.writeShellApplication {
          name = "configure-dux-lock-auth";
          runtimeInputs = [
            pkgs.jq
            pkgs.coreutils
          ];
          text = ''
            settings_file=$1
            mkdir -p "$(dirname "$settings_file")"
            source_file=$settings_file
            if [[ ! -e "$source_file" ]]; then
              source_file=/dev/null
            fi
            staged_file=$(mktemp "$settings_file.XXXXXX")
            trap 'rm -f "$staged_file"' EXIT
            jq -s 'if length == 0 then {} else .[0] end | . + {
              enableFprint: true,
              greeterEnableFprint: false,
              enableU2f: false,
              greeterEnableU2f: false,
              lockPamPath: "/etc/pam.d/dankshell",
              lockPamInlineFprint: false,
              lockPamExternallyManaged: false
            }' "$source_file" > "$staged_file"
            if ! cmp -s "$staged_file" "$settings_file"; then
              mv "$staged_file" "$settings_file"
            fi
          '';
        }
      )
    } ${lib.escapeShellArg "${config.xdg.configHome}/dms/settings.json"}
  '';
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
