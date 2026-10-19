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
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    tangleaf = {
      url = "github:okhsunrog/tangleaf";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    arctern = {
      url = "github:okhsunrog/arctern";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ayugram-plengine = {
      url = "git+https://github.com/okhsunrog/AyuGramDesktop-PLEngine?ref=linux-plengine-7.2&submodules=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    floppa-deployment = {
      url = "file+https://fgj.okhsunrog.dev/api/packages/private-artifacts/generic/floppa-deployment/1/deployment.json";
      flake = false;
    };
    floppa-vpn = {
      url = "github:okhsunrog/floppa-vpn";
      inputs.nixpkgs.follows = "nixpkgs";
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
      zen-browser,
      floppa-vpn,
      floppa-deployment,
      tangleaf,
      arctern,
      ayugram-plengine,
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
            zen-browser
            floppa-vpn
            floppa-deployment
            tangleaf
            arctern
            ayugram-plengine
            ;
        };
        modules = [
          sops-nix.nixosModules.sops
          zbm-rs.nixosModules.default
          nixos-hardware.nixosModules.framework-intel-core-ultra-series1
          ./hosts/framework
          floppa-vpn.nixosModules.default
          arctern.nixosModules.default
        ];
      };
      formatter.${system} = pkgs.nixfmt-tree;
      packages.${system} = (import ./packages/corporate.nix { inherit pkgs; }) // {
        installer = pkgs.nixos-install-tools;
        flyline = import ./packages/flyline.nix { inherit pkgs; };
        inherit (pkgs) age sops;
      };
      checks.${system} = {
        module-signing = import ./tests/module-signing.nix { inherit pkgs zbm-rs; };
        module-signing-vm = import ./tests/module-signing-vm.nix { inherit pkgs zbm-rs; };
        boot-environment = zbm-rs.checks.${system}.native-nixos;
        novpn = import ./tests/novpn.nix { inherit pkgs; };
        secrets = import ./tests/secrets.nix { inherit pkgs sops-nix; };
        corporate = import ./tests/corporate.nix { inherit pkgs; };
      };
    };
}
