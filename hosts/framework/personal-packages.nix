{
  pkgs,
  tangleaf,
  arctern,
  ...
}:
{
  environment.systemPackages = [
    (tangleaf.lib.mkPackage pkgs)
    (arctern.lib.mkPackage pkgs)
  ];
  # Replication configuration/state will be migrated separately before enabling
  # the daemon: merely installing it must not start backup or prune jobs.
}
