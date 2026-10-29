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
  # Reading JSON during evaluation does not retain its source in the closure.
  # Keep the pinned private input available for rebuilds after garbage collection.
  system.extraDependencies = [ floppa-deployment ];

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
