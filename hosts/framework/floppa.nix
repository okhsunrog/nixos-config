{ pkgs, floppa-vpn, ... }:
let
  artifacts = import ../../packages/corporate.nix { inherit pkgs; };
  deployment = builtins.fromJSON (builtins.readFile artifacts.floppa-deployment);
in
{
  services.floppa-vpn = {
    enable = true;
    autostart = true;
    users = [ "okhsunrog" ];
    guiPackage = floppa-vpn.lib.mkClient {
      inherit pkgs;
      inherit (deployment) apiUrl;
    };
  };
  systemd.services.floppa-vpn.wantedBy = [ "multi-user.target" ];
}
