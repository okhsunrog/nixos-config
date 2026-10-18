{
  description = "Framework Laptop NixOS boot environment on an existing ZFS pool";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zbm-rs.url = "github:okhsunrog/zbm-rs";
    signed-modules = {
      url = "path:/var/lib/zbm-rs-public/framework-modules";
      flake = false;
    };
    insyde-src = {
      url = "github:okhsunrog/linux-okhsunrog/9b8a40b1d56df13a463892a580465ca943bdb9ad";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixos-hardware,
      zbm-rs,
      signed-modules,
      insyde-src,
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      nixosModules.zbm-rs = zbm-rs.nixosModules.default;
      nixosConfigurations.framework = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit
            zbm-rs
            signed-modules
            insyde-src
            ;
        };
        modules = [
          zbm-rs.nixosModules.default
          nixos-hardware.nixosModules.framework-intel-core-ultra-series1
          ./hosts/framework
        ];
      };
      formatter.${system} = pkgs.nixfmt-tree;
      packages.${system} = {
        installer = pkgs.nixos-install-tools;
      };
      checks.${system} = {
        boot-environment = zbm-rs.checks.${system}.native-nixos;
      };
    };
}
