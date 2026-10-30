{
  config,
  lib,
  zbm-rs,
  signed-modules,
  insyde-src,
  ...
}:
let
  bootPkgs = import zbm-rs.inputs.nixpkgs {
    system = "x86_64-linux";
    config.allowUnfree = true;
  };
  # Match Arch's signed-policy NvPCR API without updating the kernel or
  # unrelated packages from the pinned boot package set.
  systemd262 = import ../../packages/systemd-262.nix {
    pkgs = bootPkgs;
    inherit lib;
  };
  kernelPackages = import "${zbm-rs}/nix/security-kernel.nix" {
    pkgs = bootPkgs;
    kernelPackages = bootPkgs.linuxPackages_latest;
    trustedCertificates = [
      (builtins.path {
        path = ./public/db.pem;
        name = "db.pem";
      })
      (builtins.path {
        path = ./public/ima.pem;
        name = "ima.pem";
      })
    ];
  };
  manifest = builtins.fromJSON (builtins.readFile "${signed-modules}/zbm-module-manifest.json");
  state = "/var/lib/secureboot";
  nvpcrNames = [
    "hardware"
    "cryptsetup"
    "login"
    "verity"
  ];
  # Match Arch's loader ordering in BOTH stages: measured-OS conditions may
  # cache a negative result if they run before the firmware view is repaired.
  efiRecoveryOrdering = {
    wants = [ "tpm2.target" ];
    before = [
      "systemd-udevd.service"
      "systemd-udev-trigger.service"
      "tpm2.target"
      "systemd-tpm2-setup-early.service"
      "systemd-tpm2-setup.service"
      "systemd-pcrphase-initrd.service"
      "systemd-pcrosseparator.service"
      "systemd-pcrextend.socket"
      "systemd-pcrlock.socket"
      "systemd-report-sign-tpm2.socket"
    ];
  };
in
{
  assertions = [
    {
      assertion = toString config.boot.kernelPackages.kernel == manifest.kernel_store_path;
      message = "The signed module input does not match this exact kernel derivation. Re-sign the matching aggregate module tree before rebuilding.";
    }
    {
      assertion =
        (manifest.unsigned_module_store_path or null)
        == toString config.system.build.unsignedFrameworkModules;
      message = "The signed modules do not match the current module sources. Run scripts/rebuild-framework.sh to prepare the matching signed input.";
    }
  ];
  boot.kernelPackages = kernelPackages;
  # Target-only policy: Linux applies sysctl.* before executing initramfs /init.
  # The separately constructed loader/rescue command lines keep outgoing kexec.
  boot.kernelParams = [ "sysctl.kernel.kexec_load_disabled=1" ];
  system.build.unsignedFrameworkModules = bootPkgs.aggregateModules [
    config.boot.kernelPackages.kernel.modules
    config.boot.kernelPackages.${config.boot.zfs.package.kernelModuleAttribute}
    (import "${zbm-rs}/nix/insyde-efivarfs.nix" {
      pkgs = bootPkgs;
      kernelPackages = config.boot.kernelPackages;
      sourceDirectory = insyde-src + "/modules/insyde-efivarfs";
    })
  ];
  # The normal user builds this public plan; private keys are runtime-only.
  system.build.frameworkModuleSigningPlan = bootPkgs.writeText "framework-module-signing.json" (
    builtins.toJSON {
      version = 1;
      kernel = toString config.boot.kernelPackages.kernel;
      module_version = config.boot.kernelPackages.kernel.modDirVersion;
      unsigned = toString config.system.build.unsignedFrameworkModules;
      certificate = toString (
        builtins.path {
          path = ./public/db.pem;
          name = "db.pem";
        }
      );
      sign_file = "${config.boot.kernelPackages.kernel.dev}/lib/modules/${config.boot.kernelPackages.kernel.modDirVersion}/build/scripts/sign-file";
      signer = "${zbm-rs}/nix/sign-module-tree.py";
      python = "${bootPkgs.python3}/bin/python3";
      uv = "${bootPkgs.uv}/bin/uv";
      nix_store = "${config.nix.package}/bin/nix-store";
      tool_path = lib.makeBinPath [
        bootPkgs.openssl
        bootPkgs.zstd
      ];
    }
  );
  system.modulesTree = lib.mkForce [ signed-modules ];
  boot.kernelModules = [ "insyde_efivarfs" ];
  boot.initrd.kernelModules = [ "insyde_efivarfs" ];
  boot.extraModprobeConfig = "options insyde_efivarfs expose=1\n";
  security.lsm = lib.mkForce [
    "landlock"
    "lockdown"
    "yama"
    "apparmor"
    "ima"
    "bpf"
  ];
  security.apparmor.enable = true;
  security.tpm2.enable = true;
  environment.systemPackages = [
    (bootPkgs.writeShellScriptBin "framework-rebuild" ''
      exec /etc/nixos/scripts/rebuild-framework.sh "$@"
    '')
    bootPkgs.uv
    bootPkgs.python3
    bootPkgs.openssl
    bootPkgs.zstd
    bootPkgs.sbsigntool
    bootPkgs.sbctl
  ];
  boot.loader.zbm-rs.signing = {
    enable = true;
    kernelKey = "${state}/db.key";
    kernelCertificate = "${state}/db.pem";
    imaKey = "${state}/ima.key";
    imaCertificate = "${state}/ima.pem";
    authorityKey = "${state}/db.key";
    authorityCertificate = "${state}/db.pem";
  };
  # Use the same signed-policy NvPCR API as the existing Arch installation.
  systemd.package = systemd262;
  boot.initrd.systemd.package = systemd262;
  systemd.tpm2.enable = true;
  boot.initrd.systemd.tpm2 = {
    enable = true;
    pcrphases.enable = true;
  };
  boot.initrd.secrets = {
    "/etc/systemd/tpm2-pcr-signature.json" = "/etc/systemd/tpm2-pcr-signature.json";
    "/etc/systemd/tpm2-pcr-public-key.pem" = "/etc/systemd/tpm2-pcr-public-key.pem";
  };
  boot.initrd.systemd.additionalUpstreamUnits = [
    "systemd-pcrnvdone.service"
    "systemd-pcrosseparator.service"
  ];
  # Keep the laptop's tested allocation priorities: hardware first, unused
  # verity last, so the limited physical TPM RAM does not starve login.
  environment.etc = lib.genAttrs (map (name: "nvpcr/${name}.nvpcr") nvpcrNames) (name: {
    source = insyde-src + "/modules/insyde-efivarfs/${name}";
  });
  boot.initrd.systemd.contents =
    lib.genAttrs (map (name: "/etc/nvpcr/${name}.nvpcr") nvpcrNames)
      (name: {
        source = insyde-src + "/modules/insyde-efivarfs${lib.removePrefix "/etc" name}";
      });
  systemd.services.systemd-modules-load = efiRecoveryOrdering;
  boot.initrd.systemd.services.systemd-modules-load = efiRecoveryOrdering // {
    # NixOS replaces the efivarfs view across switch-root. Leave its repaired
    # entries in place, but unload the one-shot recovery module at initrd stop
    # so the root-stage loader actually runs its init function again.
    serviceConfig.ExecStop = "${config.boot.initrd.systemd.package.kmod}/bin/modprobe -r insyde_efivarfs";
  };
  boot.initrd.systemd.services.systemd-pcrphase-initrd.after = [
    "systemd-modules-load.service"
    "initrd-nixos-copy-secrets.service"
  ];
  boot.initrd.systemd.services.systemd-pcrosseparator = {
    wantedBy = [ "sysinit.target" ];
    after = [ "systemd-modules-load.service" ];
  };
  boot.initrd.systemd.services.systemd-tpm2-setup-early = {
    wantedBy = [ "sysinit.target" ];
    after = [
      "systemd-modules-load.service"
      "initrd-nixos-copy-secrets.service"
    ];
  };
  boot.initrd.systemd.services.systemd-pcrnvdone.wantedBy = [ "sysinit.target" ];
  systemd.additionalUpstreamSystemUnits = [ "systemd-pcrproduct.service" ];
  systemd.services.systemd-pcrproduct.wantedBy = [ "sysinit.target" ];
}
