{ pkgs, framework }:
let
  cfg = framework.config;
  niri = cfg.specialisation.niri.configuration;
  lib = pkgs.lib;
  preStart =
    lib.replaceStrings
      [ "/var/lib/dms-greeter" "/home/okhsunrog" ]
      [ "$TEST_ROOT/cache" "$TEST_ROOT/home" ]
      niri.systemd.services.greetd.preStart;
  greeter = pkgs.writeShellScript "test-greeter-prepare" preStart;
in
assert cfg.systemd.user.tmpfiles.rules == [ ];
assert builtins.length cfg.home-manager.users.okhsunrog.systemd.user.tmpfiles.rules == 3;
assert builtins.length niri.home-manager.users.okhsunrog.systemd.user.tmpfiles.rules == 3;
assert lib.any (
  p: toString p.source == "${pkgs.kmod}/bin/modprobe"
) niri.boot.initrd.systemd.storePaths;
pkgs.runCommand "desktop-runtime-tests"
  {
    nativeBuildInputs = [
      pkgs.uv
      pkgs.python3
      pkgs.jq
    ];
  }
  ''
    mkdir -p cache home/.config/gtk-3.0 home/.config/gtk-4.0 bin
    export TEST_ROOT="$PWD"
    printf '#!/bin/sh\nexit 0\n' > bin/chown
    chmod +x bin/chown
    export PATH="$PWD/bin:$PATH"
    ${greeter} 2>greeter-errors
    test ! -s greeter-errors
    mkdir -p home/.cache/dms
    printf '{"background":"#123456"}\n' > home/.cache/dms/dms-colors.json
    ${greeter} 2>greeter-errors
    test ! -s greeter-errors
    cmp home/.cache/dms/dms-colors.json cache/colors.json
    printf '[Settings]\ngtk-modules=colorreload-gtk-module:custom-module:window-decorations-gtk-module\ngtk-cursor-theme-name=Bibata-Modern-Ice\n' > home/.config/gtk-3.0/settings.ini
    printf '[Settings]\ngtk-modules=window-decorations-gtk-module\ngtk-cursor-theme-name=Bibata-Modern-Ice\n' > home/.config/gtk-4.0/settings.ini
    HOME="$PWD/home" uv run --offline --no-cache --no-project --no-managed-python \
      --python ${pkgs.python3}/bin/python3 ${../hosts/framework/home/clean-niri-gtk.py}
    grep -Fx 'gtk-modules=custom-module' home/.config/gtk-3.0/settings.ini
    ! grep -q 'gtk-modules' home/.config/gtk-4.0/settings.ini
    grep -Fx 'gtk-cursor-theme-name=Bibata-Modern-Ice' home/.config/gtk-3.0/settings.ini
    cp home/.config/gtk-3.0/settings.ini original.ini
    HOME="$PWD/home" uv run --offline --no-cache --no-project --no-managed-python \
      --python ${pkgs.python3}/bin/python3 ${../hosts/framework/home/clean-niri-gtk.py}
    cmp original.ini home/.config/gtk-3.0/settings.ini
    touch $out
  ''
