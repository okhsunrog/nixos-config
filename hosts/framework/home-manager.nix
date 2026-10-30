{
  pkgs,
  config,
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
    # Collisions require explicit migration; never rename personal files on rebuild.
    extraSpecialArgs = {
      inherit
        dux-shell
        dux-calendar
        dux-files
        dux-search
        dux-gop
        ;
    };
    users.okhsunrog = {
      imports = [
        ./home/common.nix
        (if config.framework.environments.current == "niri" then ./home/niri.nix else ./home/kde.nix)
      ];
    };
  };
}
