{
  pkgs,
  tangleaf,
  ...
}:
{
  environment.systemPackages = [
    (tangleaf.lib.mkPackage pkgs)
  ];
}
