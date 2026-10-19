{ pkgs }:
let
  inherit (pkgs) lib;
  artifacts = builtins.fromJSON (builtins.readFile ./artifacts.json);
  # Unlike the curl-based nixpkgs fetchurl builder, Nix's built-in downloader
  # reads the daemon's protected netrc-file. Credentials never enter the .drv.
  fetchArtifact =
    name:
    let
      artifact = artifacts.${name};
    in
    builtins.derivation {
      name = builtins.baseNameOf artifact.url;
      system = "builtin";
      builder = "builtin:fetchurl";
      inherit (artifact) url;
      outputHash = artifact.sha256;
      outputHashAlgo = "sha256";
      outputHashMode = "flat";
      preferLocalBuild = true;
    };
in
rec {
  nac-agent = pkgs.stdenvNoCC.mkDerivation {
    pname = "nac-agent";
    inherit (artifacts.nac-agent) version;
    src = fetchArtifact "nac-agent";
    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      install -Dm755 usr/bin/nac-agent "$out/bin/nac-agent"
      runHook postInstall
    '';
    meta.platforms = [ "x86_64-linux" ];
  };
  vkey-client = pkgs.stdenvNoCC.mkDerivation {
    pname = "vkey-x509-client";
    inherit (artifacts.vkey-client) version;
    src = fetchArtifact "vkey-client";
    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      install -Dm755 vkey-x509-client-linux "$out/bin/vkey-x509-client-linux"
      install -Dm644 template.ovpn "$out/share/vkey-x509/template.ovpn"
      install -Dm644 template.ovpn.sh "$out/share/vkey-x509/template.ovpn.sh"
      install -Dm644 template-ipmi.ovpn "$out/share/vkey-x509/template-ipmi.ovpn"
      runHook postInstall
    '';
    meta.platforms = [ "x86_64-linux" ];
  };
  # These are the exact go:embed payloads in the pinned vendor client, not
  # arbitrary copies from a user's mutable installation. Hash every slice so
  # a new release cannot silently change offsets or select the wrong payload.
  vkey-runtime = pkgs.stdenvNoCC.mkDerivation {
    pname = "vkey-x509-runtime";
    inherit (artifacts.vkey-client) version;
    src = fetchArtifact "vkey-client";
    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = [ pkgs.glibc ];
    dontConfigure = true;
    dontBuild = true;
    dontStrip = true;
    installPhase =
      let
        payloads = {
          "bin/openvpn" = {
            offset = 11682272;
            size = 6784264;
            sha256 = "c69d598ae902c7762187d3646a1d38e9d65b78d969672713526cc1c5c4bf3420";
          };
          "lib/libtpm2-pkcs11.so" = {
            offset = 18466560;
            size = 6922472;
            sha256 = "6f07360408676e37b0282228f7f26158d1d92a4dbce29cfbb7a5a6b09931a899";
          };
          "bin/barbos-tray" = {
            offset = 6664480;
            size = 5017784;
            sha256 = "97ffe022e0e1e15dfb170fed460003882c93e182d93251c9060d866b44b5fc08";
          };
          "bin/vkey-fp" = {
            offset = 25389056;
            size = 8007972;
            sha256 = "040e892482bcbfa2c8f77c7a05be3f0de4947682c18268f76dff000212105349";
          };
        };
      in
      ''
        runHook preInstall
        mkdir -p "$out/bin" "$out/lib"
      ''
      + lib.concatStrings (
        lib.mapAttrsToList (name: payload: ''
          dd if=vkey-x509-client-linux of="$out/${name}" bs=1M \
            iflag=skip_bytes,count_bytes skip=${toString payload.offset} count=${toString payload.size} status=none
          echo '${payload.sha256}  '"$out/${name}" | sha256sum --check --status
        '') payloads
      )
      + ''
        chmod 755 "$out/bin/"* "$out/lib/libtpm2-pkcs11.so"
        # Remove vendor build-machine RPATHs before autoPatchelf resolves glibc.
        patchelf --remove-rpath "$out/bin/openvpn"
        runHook postInstall
      '';
    meta.platforms = [ "x86_64-linux" ];
  };
  agent-script-archive = pkgs.stdenv.mkDerivation {
    pname = "agent-script-archive";
    version = "1";
    src = ./agent-script-archive;
    nativeBuildInputs = [ pkgs.go ];
    dontConfigure = true;
    buildPhase = ''
      export HOME="$TMPDIR" CGO_ENABLED=0
      go build -trimpath -o agent-script-archive main.go
    '';
    installPhase = ''
      install -Dm755 agent-script-archive "$out/bin/agent-script-archive"
    '';
  };
  fleet-orbit = pkgs.stdenvNoCC.mkDerivation {
    pname = "fleet-orbit";
    inherit (artifacts.fleet-orbit) version;
    src = fetchArtifact "fleet-orbit";
    sourceRoot = ".";
    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = [ pkgs.glibc ];
    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/libexec/fleet-orbit" "$out/bin"
      cp -R opt/orbit/. "$out/libexec/fleet-orbit/"
      ln -s ../libexec/fleet-orbit/bin/orbit/linux/stable/orbit "$out/bin/orbit"
      ln -s ../libexec/fleet-orbit/bin/osqueryd/linux/stable/osqueryd "$out/bin/osqueryd"
      runHook postInstall
    '';
    meta.platforms = [ "x86_64-linux" ];
  };
}
