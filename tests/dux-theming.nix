{ pkgs, framework }:
let
  lib = pkgs.lib;
  cfg = framework.config;
  niri = cfg.specialisation.niri.configuration;
  engine = import ../packages/qtengine.nix { inherit pkgs; };
  dms = niri.home-manager.users.okhsunrog.programs.dank-material-shell.package;
  probe =
    major:
    let
      qt = if major == "6" then pkgs.kdePackages else pkgs.libsForQt5;
      colors = if major == "6" then pkgs.kdePackages.kcolorscheme else qt.__internalKF5.kconfigwidgets;
      breeze = if major == "6" then pkgs.kdePackages.breeze else pkgs.kdePackages.breeze.qt5;
    in
    pkgs.runCommand "dux-qt${major}-theming-test"
      {
        nativeBuildInputs = [
          pkgs.cmake
          pkgs.ninja
          pkgs.stdenv.cc
          pkgs.dbus
        ];
        buildInputs = [
          qt.qtbase
          colors
        ];
        dontWrapQtApps = true;
      }
      ''
        export HOME="$PWD/home" XDG_CONFIG_HOME="$PWD/home/.config" XDG_RUNTIME_DIR="$PWD/runtime"
        mkdir -p "$XDG_CONFIG_HOME/qtengine" "$XDG_RUNTIME_DIR"
        chmod 700 "$XDG_RUNTIME_DIR"
        cp ${./qt-theme-probe.cpp} probe.cpp
        cat > CMakeLists.txt <<'EOF'
        cmake_minimum_required(VERSION 3.16)
        project(theme_probe LANGUAGES CXX)
        find_package(Qt${major} REQUIRED COMPONENTS Widgets)
        find_package(${if major == "6" then "KF6ColorScheme" else "KF5ConfigWidgets"} REQUIRED)
        add_executable(theme-probe probe.cpp)
        target_link_libraries(theme-probe PRIVATE Qt${major}::Widgets ${
          if major == "6" then "KF6::ColorScheme" else "KF5::ConfigWidgets"
        })
        EOF
        cmake -B build -G Ninja
        cmake --build build
        cat > dark.colors <<'EOF'
        [Colors:Window]
        BackgroundNormal=20,30,40
        ForegroundNormal=240,240,240
        EOF
        cat > light.colors <<'EOF'
        [Colors:Window]
        BackgroundNormal=230,235,240
        ForegroundNormal=20,20,20
        EOF
        cp light.colors "$XDG_CONFIG_HOME/kdeglobals"
        cp "$XDG_CONFIG_HOME/kdeglobals" original-kdeglobals
        export LIGHT_SCHEME="$PWD/light.colors"
        printf '{"theme":{"colorScheme":"%s/dark.colors","style":"breeze"}}' "$PWD" > "$XDG_CONFIG_HOME/qtengine/config.json"
        export QT_QPA_PLATFORM=offscreen
        export QT_PLUGIN_PATH="${engine}/${qt.qtbase.qtPluginPrefix}:${breeze}/${qt.qtbase.qtPluginPrefix}:${qt.qtbase}/${qt.qtbase.qtPluginPrefix}"
        cat > session-bus.conf <<EOF
        <busconfig>
          <type>session</type>
          <listen>unix:tmpdir=$XDG_RUNTIME_DIR</listen>
          <policy context="default">
            <allow own="*"/><allow send_destination="*"/><allow receive_sender="*"/>
          </policy>
        </busconfig>
        EOF
        QT_QPA_PLATFORMTHEME=qtengine dbus-run-session --config-file=session-bus.conf -- build/theme-probe niri
        QT_QPA_PLATFORMTHEME=generic build/theme-probe kde
        cmp original-kdeglobals "$XDG_CONFIG_HOME/kdeglobals"
        mkdir -p "$out/bin"
        cp build/theme-probe "$out/bin/qt${major}-theme-probe"
      '';
in
assert niri.environment.sessionVariables.QT_QPA_PLATFORMTHEME == "qtengine";
assert (cfg.environment.sessionVariables.QT_QPA_PLATFORMTHEME or null) != "qtengine";
assert lib.hasPrefix "/home/okhsunrog/.local/share/niri:"
  niri.environment.sessionVariables.XDG_DATA_DIRS;
assert
  !(lib.hasInfix "/home/okhsunrog/.local/share/niri" cfg.environment.sessionVariables.XDG_DATA_DIRS);
pkgs.runCommand "dux-desktop-theme-isolation"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
    ];
    passthru = {
      qt5 = probe "5";
      qt6 = probe "6";
    };
  }
  ''
    # Building both dependencies executes palette, KDE integration and live
    # reloading checks against the real Qt5 and Qt6 plugins.
    test -x ${probe "5"}/bin/qt5-theme-probe
    test -x ${probe "6"}/bin/qt6-theme-probe
    export HOME="$PWD/home" XDG_CONFIG_HOME="$PWD/home/.config"
    export DMS_GTK_DATA_HOME="$HOME/.local/share/niri"
    export DMS_GTK_THEME_PREFIX=Dux-
    export DMS_MANAGE_GTK=1
    export XDG_DATA_DIRS="$DMS_GTK_DATA_HOME:${pkgs.adw-gtk3}/share"
    mkdir -p "$HOME/.local/share/themes/adw-gtk3/gtk-3.0" "$XDG_CONFIG_HOME/gtk-3.0" "$XDG_CONFIG_HOME/gtk-4.0"
    echo 'KDE personal theme: preserve me' > "$HOME/.local/share/themes/adw-gtk3/gtk-3.0/gtk.css"
    cp "$HOME/.local/share/themes/adw-gtk3/gtk-3.0/gtk.css" kde-theme-original
    echo '@define-color window_bg_color #141e28;' | tee "$XDG_CONFIG_HOME/gtk-3.0/dank-colors.css" > "$XDG_CONFIG_HOME/gtk-4.0/dank-colors.css"
    bash ${dms}/share/quickshell/dms/scripts/gtk.sh "$XDG_CONFIG_HOME" patch false
    grep -q '#141e28' "$DMS_GTK_DATA_HOME/themes/Dux-adw-gtk3-dark/gtk-3.0/gtk.css"
    grep -q 'dank-colors.css' "$XDG_CONFIG_HOME/gtk-4.0/gtk.css"
    # Upgrade from an already enabled shared GTK theme: the import can exist
    # before the new private resource directory does.
    rm -rf "$DMS_GTK_DATA_HOME/themes"
    bash ${dms}/share/quickshell/dms/scripts/gtk.sh "$XDG_CONFIG_HOME" patch false
    grep -q '#141e28' "$DMS_GTK_DATA_HOME/themes/Dux-adw-gtk3-dark/gtk-3.0/gtk.css"
    cmp kde-theme-original "$HOME/.local/share/themes/adw-gtk3/gtk-3.0/gtk.css"
    touch "$out"
  ''
