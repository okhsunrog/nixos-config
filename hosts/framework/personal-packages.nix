{
  pkgs,
  tangleaf,
  ...
}:
let
  orcaSlicer = pkgs.symlinkJoin {
    name = "orca-slicer-${pkgs.orca-slicer.version}";
    paths = [ pkgs.orca-slicer ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    # WebKit's DMA-BUF renderer produces a blank Home page on this Intel/KWin
    # setup. Keep this workaround local to the slicer, including desktop launch.
    postBuild = ''
      wrapProgram "$out/bin/orca-slicer" --set WEBKIT_DISABLE_DMABUF_RENDERER 1
    '';
    inherit (pkgs.orca-slicer) meta;
  };
in
{
  environment.systemPackages = [
    (tangleaf.lib.mkPackage pkgs)
    (pkgs.callPackage ../../packages/chatgpt.nix { })
    orcaSlicer
  ];
}
