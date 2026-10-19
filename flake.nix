{
  description = "Framework Laptop NixOS boot environment on an existing ZFS pool";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    host-secrets = {
      url = "git+https://fgj.okhsunrog.dev/okhsunrog/nixos-secrets.git?ref=main";
      flake = false;
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
      sops-nix,
      host-secrets,
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
            host-secrets
            ;
        };
        modules = [
          sops-nix.nixosModules.sops
          zbm-rs.nixosModules.default
          nixos-hardware.nixosModules.framework-intel-core-ultra-series1
          ./hosts/framework
        ];
      };
      formatter.${system} = pkgs.nixfmt-tree;
      packages.${system} = (import ./packages/corporate.nix { inherit pkgs; }) // {
        installer = pkgs.nixos-install-tools;
        flyline = import ./packages/flyline.nix { inherit pkgs; };
        inherit (pkgs) age sops;
      };
      checks.${system} = {
        boot-environment = zbm-rs.checks.${system}.native-nixos;
        secrets = import ./tests/secrets.nix { inherit pkgs sops-nix; };
        corporate = import ./tests/corporate.nix { inherit pkgs; };
      };
    };
}
