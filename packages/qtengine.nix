{ pkgs }:
let
  qt5 = pkgs.libsForQt5;
  kf5 = qt5.__internalKF5;
  qt5Plugin = pkgs.stdenv.mkDerivation {
    pname = "qtengine-qt5";
    inherit (pkgs.qtengine) version src meta;
    nativeBuildInputs = [
      pkgs.cmake
      pkgs.ninja
      pkgs.kdePackages.extra-cmake-modules
    ];
    buildInputs = [
      qt5.qtbase
      kf5.kconfig
      kf5.kconfigwidgets
      kf5.kiconthemes
    ];
    cmakeFlags = [
      "-DBUILD_QT5=ON"
      "-DBUILD_QT6=OFF"
      "-DQT5_PLUGINDIR=${placeholder "out"}/${qt5.qtbase.qtPluginPrefix}"
      "-DQT5_LIBDIR=${placeholder "out"}/lib"
    ];
    dontWrapQtApps = true;
  };
in
# Build the two major versions separately: Nix's Qt hooks intentionally reject
# mixed Qt dependencies in a single derivation. Both use the pinned 0.2.2 source.
pkgs.symlinkJoin {
  name = "qtengine-${pkgs.qtengine.version}-qt5-qt6";
  paths = [
    qt5Plugin
    pkgs.qtengine
  ];
  passthru = {
    qt5 = qt5Plugin;
    qt6 = pkgs.qtengine;
  };
}
