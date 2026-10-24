{
  pkgs,
  home-manager,
  dux-shell,
  dux-calendar,
  dux-files,
  dux-search,
  dux-gop,
  ...
}:
{
  imports = [ home-manager.nixosModules.home-manager ];
  environment.systemPackages = [
    home-manager.packages.${pkgs.stdenv.hostPlatform.system}.home-manager
  ];
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "before-dux-20261024";
    extraSpecialArgs = {
      inherit
        dux-shell
        dux-calendar
        dux-files
        dux-search
        dux-gop
        ;
    };
  };
}
