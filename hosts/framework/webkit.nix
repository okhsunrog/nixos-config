{ pkgs, nixpkgs-webkit, ... }:
let
  fixedPkgs = import nixpkgs-webkit { system = pkgs.stdenv.hostPlatform.system; };
in
{
  # Use the exact GTK 3 / libsoup 3 build validated with Skia on Niri.
  # Remove this pin once the primary nixpkgs supplies WebKitGTK >= 2.54.2.
  nixpkgs.overlays = [ (_final: _prev: { webkitgtk_4_1 = fixedPkgs.webkitgtk_4_1; }) ];
}
