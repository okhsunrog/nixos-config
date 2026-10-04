{
  description = "Framework Laptop NixOS boot environment on an existing ZFS pool";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixos-hardware,
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      nixosModules.zfsbootmenu = import ./modules/zfsbootmenu.nix;
      nixosConfigurations.framework = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          self.nixosModules.zfsbootmenu
          nixos-hardware.nixosModules.framework-intel-core-ultra-series1
          ./hosts/framework
        ];
      };
      formatter.${system} = pkgs.nixfmt-tree;
      packages.${system}.installer = pkgs.nixos-install-tools;
      checks.${system} = {
        boot-environment = import ./tests/boot-environment.nix {
          inherit pkgs;
          module = self.nixosModules.zfsbootmenu;
        };
        niri-config = pkgs.runCommand "niri-config-validation" { } ''
          ${pkgs.niri}/bin/niri validate --config ${./hosts/framework/niri.kdl}
          touch $out
        '';
      };
    };
}
