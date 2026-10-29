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
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    dux-shell = {
      url = "github:duxlabs-dev/dux-shell/v2.0.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    dux-greeter = {
      url = "github:duxlabs-dev/dux-greeter/v2.0.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.dank-qml-common.follows = "dux-shell/dank-qml-common";
    };
    dux-search = {
      url = "github:duxlabs-dev/dux-search/v2.0.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    dux-gop = {
      url = "github:duxlabs-dev/dux-gop/v2.0.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    dux-calendar = {
      url = "github:duxlabs-dev/dux-calendar/v2.0.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.dank-qml-common.follows = "dux-shell/dank-qml-common";
    };
    dux-files = {
      url = "github:duxlabs-dev/dux-files/v2.0.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.dank-qml-common.follows = "dux-shell/dank-qml-common";
    };
    rio-src = {
      url = "github:okhsunrog/rio/nixos-main-with-fixes";
      flake = false;
    };
    # Temporary power-loss diagnostic build. This immutable source is retained
    # by the installed EFI plan; restore the GitHub input after the investigation.
    zbm-rs.url = "path:/nix/store/hk5nwbb1vb57r0v2s9rwabxa0icqkpbg-source";
    zbm-rescue.url = "github:okhsunrog/zbm-rs/4038ff09a44c674fc1b4b1126b0f21aa4d09706a";
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
      rio-src,
      home-manager,
      dux-shell,
      dux-greeter,
      dux-search,
      dux-gop,
      dux-calendar,
      dux-files,
      nixpkgs,
      nixos-hardware,
      sops-nix,
      host-secrets,
      zbm-rs,
      zbm-rescue,
      signed-modules,
      insyde-src,
      zen-browser,
      floppa-vpn,
      floppa-deployment,
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
          rio = self.packages.${system}.rio;
          inherit
            home-manager
            dux-shell
            dux-greeter
            dux-search
            dux-gop
            dux-calendar
            dux-files
            zbm-rs
            zbm-rescue
            signed-modules
            insyde-src
            host-secrets
            zen-browser
            floppa-vpn
            floppa-deployment
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
        dux-suite = pkgs.symlinkJoin {
          name = "dux-suite-2.0.0";
          paths = [
            dux-shell.packages.${system}.default
            dux-greeter.packages.${system}.default
            dux-search.packages.${system}.default
            dux-gop.packages.${system}.default
            dux-calendar.packages.${system}.default
            dux-files.packages.${system}.default
            pkgs.quickshell
          ];
        };
        rio = import ./packages/rio.nix {
          inherit pkgs;
          src = rio-src;
        };
        installer = pkgs.nixos-install-tools;
        boot-environment-test = zbm-rs.checks.${system}.native-nixos;
        flyline = import ./packages/flyline.nix { inherit pkgs; };
        inherit (pkgs) age sops;
      };
      checks.${system} = {
        environments = import ./tests/environments.nix {
          inherit pkgs;
          framework = self.nixosConfigurations.framework;
        };
        environments-vm = import ./tests/environments-vm.nix {
          inherit
            pkgs
            nixpkgs
            home-manager
            zbm-rs
            system
            ;
        };
        plasma-login-auth = import ./tests/plasma-login-auth.nix { inherit pkgs; };
        module-signing = import ./tests/module-signing.nix { inherit pkgs zbm-rs; };
        module-signing-vm = import ./tests/module-signing-vm.nix { inherit pkgs zbm-rs; };
        novpn = import ./tests/novpn.nix { inherit pkgs; };
        secrets = import ./tests/secrets.nix { inherit pkgs sops-nix; };
        corporate = import ./tests/corporate.nix { inherit pkgs; };
        pantum-duplex = import ./tests/pantum-duplex.nix {
          pkgs = self.nixosConfigurations.framework.pkgs;
        };
      };
    };
}
