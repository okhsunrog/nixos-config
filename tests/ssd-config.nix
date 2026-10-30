{
  pkgs,
  framework,
  ssd,
}:
let
  lib = pkgs.lib;
  cfg = ssd.config;
  niri = cfg.specialisation.niri.configuration;
  onlyExternal =
    c:
    lib.all (fs: fs.fsType != "zfs" || lib.hasPrefix "nova_external/" fs.device) (
      lib.attrValues c.fileSystems
    );
in
assert framework.config.fileSystems."/".device == "novafs/nixos0/root";
assert framework.config.boot.loader.zbm-rs.efi.label == "zbm-rs";
assert cfg.fileSystems."/".device == "nova_external/nixos0/root";
assert cfg.fileSystems."/home".device == "nova_external/nixos0/data/home";
assert onlyExternal cfg && onlyExternal niri;
assert !(cfg.fileSystems ? "/home/okhsunrog/Nextcloud");
assert !cfg.services.arctern.enable && !cfg.systemd.services.arctern.enable;
assert cfg.framework.environments.entries.kde.backup == "none";
assert cfg.framework.environments.entries.niri.backup == "none";
assert cfg.boot.loader.zbm-rs.efi.partuuid == "8494cd60-68e6-4ab9-991b-10f82988f3e0";
assert cfg.boot.loader.zbm-rs.efi.label == "zbm-rs (SSD)";
assert lib.all (m: builtins.elem m cfg.boot.initrd.availableKernelModules) [
  "usb_storage"
  "uas"
  "sd_mod"
];
assert
  cfg.boot.zfs.requestEncryptionCredentials == [
    "nova_external/nixos0/root"
    "nova_external/nixos0/data/home"
  ];
assert lib.all (a: a.assertion) cfg.assertions;
assert lib.all (a: a.assertion) niri.assertions;
pkgs.runCommand "framework-ssd-config-test"
  {
    nativeBuildInputs = [
      pkgs.uv
      pkgs.python3
    ];
    EFI_PREPARE = "${../scripts/prepare-framework-loader.py}";
  }
  ''
    uv run --offline --no-cache --no-project --no-managed-python \
      --python ${pkgs.python3}/bin/python3 ${./test_loader_target_root.py}
    touch $out
  ''
