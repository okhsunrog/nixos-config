{
  pkgs,
  floppa-vpn,
  floppa-deployment,
  ...
}:
let
  deployment = builtins.fromJSON (builtins.readFile floppa-deployment);
in
{
  services.floppa-vpn = {
    enable = true;
    autostart = true;
    keepBuildDependencies = true;
    users = [ "okhsunrog" ];
    guiPackage = floppa-vpn.lib.mkClient {
      inherit pkgs;
      inherit (deployment) apiUrl;
    };
  };
  systemd.services.floppa-vpn.wantedBy = [ "multi-user.target" ];
}
