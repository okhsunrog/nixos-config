{
  config,
  lib,
  zbm-rs,
  zbm-rescue,
  insyde-src,
  ...
}:
let
  system = "x86_64-linux";
  pkgs = import zbm-rs.inputs.nixpkgs { inherit system; };
  rescuePkgs = import zbm-rescue.inputs.nixpkgs { inherit system; };
  esp = config.framework.storage.espPartuuid;
  state = "/var/lib/zbm-rs-signing";
  certificate = builtins.path {
    path = ./public/db.pem;
    name = "db.pem";
  };
  imaCertificate = builtins.path {
    path = ./public/ima.pem;
    name = "ima.pem";
  };
  hardware = pkgs.writeText "framework-boot-hardware.json" (
    builtins.toJSON {
      schemaVersion = 1;
      modules = [
        "nvme"
        "xhci_pci"
        "usbhid"
        "hid_generic"
        "atkbd"
        "i8042"
      ]
      ++ lib.optionals config.framework.storage.portable [
        "usb_storage"
        "uas"
        "sd_mod"
      ];
      firmwarePaths = [ ];
    }
  );
  image = zbm-rs.lib.mkImage {
    inherit pkgs imaCertificate;
    kernelPackages = config.boot.kernelPackages;
    kernelPolicy = "validate";
    profile = "host-only";
    hardwareManifest = hardware;
    hostId = config.networking.hostId;
    # Apply the same Intel CPU fixes before the loader kernel starts as in NixOS.
    microcodeInitrd = "${config.hardware.cpu.intel.microcodePackage}/intel-ucode.img";
    # Retain symbols/line tables and read-only power/temperature telemetry while
    # investigating intermittent power loss during the passphrase prompt.
    rustProfile = {
      debug = 1;
      strip = "none";
    };
    extraModules = [
      "coretemp"
      "battery"
      "ac"
    ];
    targetAuthorities = [ certificate ];
    extraModulePackages = kernelPackages: [
      (import "${zbm-rs}/nix/insyde-efivarfs.nix" {
        inherit pkgs kernelPackages;
        sourceDirectory = insyde-src + "/modules/insyde-efivarfs";
      })
    ];
    forcedModules = [ "insyde_efivarfs" ];
    moduleOptions.insyde_efivarfs = "expose=1";
    loaderConfig = {
      boot = {
        mode = "menu";
      }
      // lib.optionalAttrs (config.framework.storage.preferredPoolGuid != null) {
        preferred_pool_guid = config.framework.storage.preferredPoolGuid;
      };
      diagnostics = {
        esp_partuuid = esp;
        continuous = true;
      };
      ui.title = "zbm-rs diagnostic";
      ui.show_snapshots = true;
      zfs.import_policy = "host-id";
      security = {
        mode = "enforce";
        require_firmware_secure_boot = true;
        tpm.policy = "optional";
      };
    };
  };
  # A separate immutable source and package set. No follows or moving branch.
  rescue = zbm-rescue.lib.mkImage {
    pkgs = rescuePkgs;
    kernelPackages = rescuePkgs.linuxPackages_latest;
    hostId = config.networking.hostId;
    extraModulePackages = kernelPackages: [
      (import "${zbm-rescue}/nix/insyde-efivarfs.nix" {
        pkgs = rescuePkgs;
        inherit kernelPackages;
        sourceDirectory = insyde-src + "/modules/insyde-efivarfs";
      })
    ];
    # Keep the Framework repair module available without making portable rescue
    # startup depend on this firmware-specific module successfully initializing.
    extraModules = [ "insyde_efivarfs" ];
    moduleOptions.insyde_efivarfs = "expose=1";
    loaderConfig = {
      boot.mode = "menu";
      ui = {
        show_snapshots = true;
        title = "zbm-rs rescue";
      };
      zfs.import_policy = "host-id";
      security = {
        mode = "off";
        require_firmware_secure_boot = false;
        tpm.policy = "off";
      };
    };
  };
  deployment = "${state}/loader/${builtins.baseNameOf image}";
  toolPath = lib.makeBinPath [
    pkgs.coreutils
    pkgs.util-linux
    pkgs.efibootmgr
    pkgs.dosfstools
    pkgs.openssl
    pkgs.zstd
    pkgs.cpio
    pkgs.sbsigntool
    pkgs.uv
    pkgs.python3
  ];
in
{
  boot.loader.zbm-rs.efi = {
    enable = true;
    image = "${deployment}/esp/EFI/BOOT/BOOTX64.EFI";
    certificate = "/var/lib/secureboot/db.pem";
    partuuid = esp;
    label = config.framework.storage.efiLabel;
  };
  # Retain the exact unsigned image and signing tools with each OS generation.
  system.extraDependencies = [ config.system.build.frameworkEfiPlan ];
  system.build.frameworkEfiPlan = pkgs.writeText "framework-efi-plan.json" (
    builtins.toJSON {
      version = 1;
      rootDataset = config.framework.storage.rootDataset;
      image = toString image;
      certificate = toString certificate;
      inherit deployment toolPath;
      publisher = "${zbm-rs}/nix/publish-loader.py";
      installer = "${zbm-rs}/nix/install-efi.py";
      signFile = "${image.kernel.dev}/lib/modules/${image.kernel.modDirVersion}/build/scripts/sign-file";
      evmctl = "${pkgs.ima-evm-utils}/bin/evmctl";
      ukify = "${pkgs.systemdUkify}/bin/ukify";
      measure = "${config.systemd.package}/lib/systemd/systemd-measure";
      pcrKey = "/var/lib/secureboot/pcr.key";
      pcrPublicKey = "/etc/systemd/tpm2-pcr-public-key.pem";
      pcrSignatures = "/etc/systemd/tpm2-pcr-signature.json";
      efi = {
        partuuid = esp;
        path = "EFI/zbm-rs/zbm-rs.EFI";
        label = config.framework.storage.efiLabel;
        certificate = "/var/lib/secureboot/db.pem";
      };
    }
  );
  system.build.frameworkRescuePlan = pkgs.writeText "framework-rescue-plan.json" (
    builtins.toJSON {
      version = 1;
      image = "${rescue}/esp/EFI/BOOT/BOOTX64.EFI";
      installer = "${zbm-rs}/nix/install-efi.py";
      inherit toolPath;
      efi = {
        partuuid = esp;
        path = "EFI/zbm-rs/rescue.EFI";
        label = "zbm-rs (rescue)";
        certificate = null;
      };
    }
  );
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "framework-rescue-update" ''
      exec /etc/nixos/scripts/update-framework-rescue.sh "$@"
    '')
    pkgs.efibootmgr
  ];
}
