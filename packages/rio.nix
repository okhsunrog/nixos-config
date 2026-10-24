{ pkgs, src }:
(pkgs.rio.override { }).overrideAttrs (old: {
  version = "0.5.28-main-${builtins.substring 0 8 src.rev}";
  inherit src;
  cargoDeps = pkgs.rustPlatform.importCargoLock { lockFile = "${src}/Cargo.lock"; };
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
  # Include the configuration/theme tests as well as the terminal keyboard tests.
  cargoTestFlags = [
    "-p"
    "rioterm"
    "-p"
    "rio-backend"
    "-p"
    "rio-vt"
  ];
  buildInputs = old.buildInputs ++ [
    pkgs.alsa-lib
    pkgs.oniguruma
  ];
  runtimeDependencies = old.runtimeDependencies ++ [ pkgs.alsa-lib ];
  RUSTONIG_DYNAMIC_LIBONIG = "1";
  CARGO_PROFILE_RELEASE_LTO = "thin";
  postPatch = (old.postPatch or "") + ''
    substituteInPlace misc/com.rioterm.Rio.metainfo.xml \
      --replace-fail 'com.rioterm.Rio.desktop' 'rio.desktop'
  '';
  postInstall = old.postInstall + ''
    install -D -m 644 misc/com.rioterm.Rio.metainfo.xml -t $out/share/metainfo
  '';
  meta = old.meta // {
    homepage = "https://github.com/okhsunrog/rio/tree/nixos-main-with-fixes";
  };
})
