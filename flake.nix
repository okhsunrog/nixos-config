{
  description = "Framework Laptop NixOS boot environment on an existing ZFS pool";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
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
    rio-src = {
      url = "github:okhsunrog/rio/11b8a338473898ff5d012f890eb0df06f66a8e2f";
      flake = false;
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixos-hardware,
      rio-src,
      rust-overlay,
      zbm-rs,
      signed-modules,
      insyde-src,
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      rustPkgs = import nixpkgs {
        inherit system;
        overlays = [ (import rust-overlay) ];
      };
      rio = pkgs.callPackage ./packages/rio.nix {
        src = rio-src;
        rustToolchain = rustPkgs.rust-bin.stable."1.96.1".minimal;
      };
    in
    {
      nixosModules.zbm-rs = zbm-rs.nixosModules.default;
      nixosConfigurations.framework = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit
            rio
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
        inherit rio;
      };
      checks.${system} = {
        boot-environment = zbm-rs.checks.${system}.native-nixos;
        niri-config = pkgs.runCommand "niri-config-validation" { } ''
          ${pkgs.niri}/bin/niri validate --config ${./hosts/framework/niri.kdl}
          touch $out
        '';
      };
    };
}
