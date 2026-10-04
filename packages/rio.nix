{
  pkgs,
  src,
  rustToolchain,
}:
let
  rustPlatform = pkgs.makeRustPlatform {
    cargo = rustToolchain;
    rustc = rustToolchain;
  };
in
(pkgs.rio.override { inherit rustPlatform; }).overrideAttrs (old: {
  version = "0.5.28-okhsunrog-11b8a338";
  inherit src;
  cargoDeps = rustPlatform.importCargoLock { lockFile = "${src}/Cargo.lock"; };
  postPatch = ''
    substituteInPlace misc/com.rioterm.Rio.metainfo.xml \
      --replace-fail 'com.rioterm.Rio.desktop' 'rio.desktop'
  '';
  cargoBuildFlags = [
    "-p"
    "rioterm"
  ];
  cargoTestFlags = [
    "-p"
    "rioterm"
  ];
  cargoBuildFeatures = [
    "x11"
    "wayland"
    "wgpu"
    "audio"
  ];
  cargoCheckFeatures = [
    "x11"
    "wayland"
    "wgpu"
    "audio"
  ];
  buildInputs = old.buildInputs ++ [
    pkgs.alsa-lib
    pkgs.oniguruma
  ];
  runtimeDependencies = old.runtimeDependencies ++ [ pkgs.alsa-lib ];
  RUSTONIG_DYNAMIC_LIBONIG = "1";
  CARGO_PROFILE_RELEASE_LTO = "thin";
  postInstall = old.postInstall + ''
    install -D -m 644 misc/com.rioterm.Rio.metainfo.xml \
      -t $out/share/metainfo
  '';
  meta = old.meta // {
    homepage = "https://github.com/okhsunrog/rio";
  };
})
