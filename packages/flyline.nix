{ pkgs }:
pkgs.stdenvNoCC.mkDerivation rec {
  pname = "flyline";
  version = "1.10.0";
  src = pkgs.fetchurl {
    url = "https://github.com/HalFrgrd/flyline/releases/download/v${version}/libflyline-v${version}-x86_64-unknown-linux-gnu.tar.gz";
    sha256 = "ff666c3c8d982e3a0bb08d1a515a19da4719af4721649220c9be3d008f260beb";
  };
  sourceRoot = ".";
  nativeBuildInputs = [ pkgs.autoPatchelfHook ];
  buildInputs = [ pkgs.stdenv.cc.cc.lib ];
  dontConfigure = true;
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    install -Dm755 libflyline.so.${version} "$out/lib/libflyline.so"
    runHook postInstall
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    ${pkgs.bashInteractive}/bin/bash --noprofile --norc -i -c \
      'enable -f "$1" flyline; enable -p | grep -q "enable flyline"' \
      flyline-install-check "$out/lib/libflyline.so"
  '';
  meta = {
    description = "Official Flyline Bash line editor release";
    homepage = "https://github.com/HalFrgrd/flyline";
    license = pkgs.lib.licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
  };
}
