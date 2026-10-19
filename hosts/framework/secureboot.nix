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
in
{
  assertions = [
    {
      assertion = toString config.boot.kernelPackages.kernel == manifest.kernel_store_path;
      message = "The signed module input does not match this exact kernel derivation. Re-sign the matching aggregate module tree before rebuilding.";
    }
  ];
  boot.kernelPackages = kernelPackages;
  system.build.unsignedFrameworkModules = bootPkgs.aggregateModules [
    config.boot.kernelPackages.kernel.modules
    config.boot.kernelPackages.zfs
    (import "${zbm-rs}/nix/insyde-efivarfs.nix" {
      pkgs = bootPkgs;
      kernelPackages = config.boot.kernelPackages;
      sourceDirectory = insyde-src + "/modules/insyde-efivarfs";
    })
  ];
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
  boot.initrd.systemd.services.systemd-modules-load = {
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
