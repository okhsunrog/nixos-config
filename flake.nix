{
  description = "Framework Laptop NixOS boot environment on an existing ZFS pool";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # WebKitGTK animation-completion fix, pending nixpkgs PR #578459.
    nixpkgs-webkit.url = "github:NixOS/nixpkgs/512527cdaf7eab2f9e4c5e6e3935c1648d156621";
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
    niri-upstream = {
      url = "github:niri-wm/niri/fcbc971cf49a987b1e8d5ff1d64da6b1f61a1787";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zbm-rs.url = "github:okhsunrog/zbm-rs/1123d7307abd0a1eb48433ac68918f2965ba7cca";
    # Independently pinned cancellation-only baseline; ordinary updates to the
    # main loader must not move this input or replace the known-good EFI slot.
    zbm-rescue.url = "github:okhsunrog/zbm-rs/dc82575eb2d0b9cd9e9db1dafc4172838db8b585";
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
      niri-upstream,
      home-manager,
      dux-shell,
      dux-greeter,
      dux-search,
      dux-gop,
      dux-calendar,
      dux-files,
      nixpkgs,
      nixpkgs-webkit,
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
          inherit nixpkgs-webkit;
          rio = self.packages.${system}.rio;
          niriPatched = self.packages.${system}.niri;
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
      nixosConfigurations.framework-ssd = self.nixosConfigurations.framework.extendModules {
        modules = [ ./hosts/framework/ssd.nix ];
      };
      formatter.${system} = pkgs.nixfmt-tree;
      packages.${system} = (import ./packages/corporate.nix { inherit pkgs; }) // {
        niri = import ./packages/niri.nix { inherit niri-upstream system; };
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
        ssd-config = import ./tests/ssd-config.nix {
          inherit pkgs;
          framework = self.nixosConfigurations.framework;
          ssd = self.nixosConfigurations.framework-ssd;
        };
        ssd-storage-vm = import ./tests/ssd-storage-vm.nix {
          inherit
            pkgs
            nixpkgs
            zbm-rs
            system
            ;
        };
        desktop-runtime = import ./tests/desktop-runtime.nix {
          inherit pkgs;
          framework = self.nixosConfigurations.framework;
        };
        dux-cursor = import ./tests/dux-cursor.nix {
          inherit pkgs;
          dms =
            self.nixosConfigurations.framework.config.specialisation.niri.configuration.home-manager.users.okhsunrog.programs.dank-material-shell.package;
        };
        niri-capture-config = import ./tests/niri-capture-config.nix {
          inherit pkgs;
          niri = self.packages.${system}.niri;
        };
        private-inputs = import ./tests/private-inputs.nix { inherit pkgs; };
        environments = import ./tests/environments.nix {
          inherit pkgs;
          framework = self.nixosConfigurations.framework;
          niriPackage = self.packages.${system}.niri;
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
        plasma-login-auth = import ./tests/plasma-login-auth.nix {
          inherit pkgs;
          framework = self.nixosConfigurations.framework;
        };
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
