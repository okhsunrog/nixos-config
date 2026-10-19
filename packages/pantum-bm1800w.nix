{
  lib,
  stdenvNoCC,
  autoPatchelfHook,
  cups,
}:
let
  artifact = (builtins.fromJSON (builtins.readFile ./artifacts.json)).pantum-bm1800w-print;
in
stdenvNoCC.mkDerivation {
  pname = "pantum-bm1800w-print";
  inherit (artifact) version;
  # The built-in downloader uses the daemon's runtime netrc, outside the store.
  src = builtins.derivation {
    name = builtins.baseNameOf artifact.url;
    system = "builtin";
    builder = "builtin:fetchurl";
    inherit (artifact) url;
    outputHash = artifact.sha256;
    outputHashAlgo = "sha256";
    outputHashMode = "flat";
    preferLocalBuild = true;
  };
  sourceRoot = ".";
  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ cups ];
  dontConfigure = true;
  dontBuild = true;
  installPhase = ''
    install -Dm755 usr/lib/cups/filter/ptm2300gdiFilter "$out/lib/cups/filter/ptm2300gdiFilter"
    install -Dm644 usr/share/licenses/pantum-bm1800w-print/LICENSE "$out/share/licenses/pantum-bm1800w-print/LICENSE"
  '';
  meta = {
    description = "Pantum BM1800W raster filter, preserved from the working Arch installation";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
  };
}
