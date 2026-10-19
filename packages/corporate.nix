{ pkgs }:
let
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
{
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
