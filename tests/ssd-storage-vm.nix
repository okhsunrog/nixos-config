{
  pkgs,
  nixpkgs,
  zbm-rs,
  system,
}:
let
  target =
    (import "${nixpkgs}/nixos/lib/eval-config.nix" {
      inherit system;
      modules = [
        zbm-rs.nixosModules.default
        ../hosts/framework/storage.nix
        "${nixpkgs}/nixos/modules/profiles/qemu-guest.nix"
        "${nixpkgs}/nixos/modules/testing/test-instrumentation.nix"
        {
          networking.hostName = "ssd-key-test";
          networking.hostId = "00bab10c";
          framework.storage = {
            pool = "externaltest";
            portable = true;
            swapLuksUuid = "11111111-2222-4333-8444-555555555555";
            encryptionRoots = [
              "externaltest"
              "externaltest/nixos0/root"
              "externaltest/nixos0/data/home"
              "externaltest/nextcloud"
              "externaltest/tmp_zfs_home"
            ];
          };
          boot.zfs.devNodes = "/dev/disk/by-path";
          boot.kernelParams = [ "console=ttyS0" ];
          fileSystems."/home" = {
            device = "externaltest/nixos0/data/home";
            fsType = "zfs";
            options = [ "zfsutil" ];
            neededForBoot = true;
          };
          system.stateVersion = "26.05";
        }
      ];
    }).config.system.build.toplevel;
  loader = zbm-rs.packages.${system}.zbm-rs;
  imageConfig = pkgs.writeText "ssd-test-image-config" "{}";
in
pkgs.testers.runNixOSTest {
  name = "framework-ssd-independent-keys";
  globalTimeout = 600;
  nodes.machine = {
    networking.hostId = "00bab10c";
    boot.supportedFilesystems = [ "zfs" ];
    virtualisation.memorySize = 3072;
    virtualisation.emptyDiskImages = [
      16000
      512
    ];
    virtualisation.additionalPaths = [ target ];
    environment.systemPackages = [
      pkgs.zfs
      pkgs.kexec-tools
      pkgs.nixos-install-tools
      pkgs.cryptsetup
    ];
  };
  testScript = ''
    import json, shlex
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("mkdir -p /etc/zfs; printf disposable-test-only > /etc/zfs/zroot.key; chmod 600 /etc/zfs/zroot.key")
    machine.succeed("zpool create -O mountpoint=none -O encryption=aes-256-gcm -O keyformat=passphrase -O keylocation=file:///etc/zfs/zroot.key externaltest /dev/vdb; zfs create -p -o mountpoint=none externaltest/nixos0/data")
    for dataset, mountpoint in [("externaltest/nixos0/root", "/"), ("externaltest/nixos0/data/home", "/home"), ("externaltest/nextcloud", "/home/okhsunrog/Nextcloud"), ("externaltest/tmp_zfs_home", "/home/okhsunrog/tmp_zfs")]:
        machine.succeed(f"zfs create -o encryption=aes-256-gcm -o keyformat=passphrase -o keylocation=file:///etc/zfs/zroot.key -o canmount=noauto -o mountpoint={mountpoint} {dataset}")
    machine.succeed("cryptsetup luksFormat --batch-mode --type luks2 --uuid 11111111-2222-4333-8444-555555555555 --key-file /etc/zfs/zroot.key /dev/vdc; cryptsetup open --key-file /etc/zfs/zroot.key /dev/vdc nvme-swap; mkswap /dev/mapper/nvme-swap; cryptsetup close nvme-swap")
    machine.succeed("mkdir -p /mnt; mount -t zfs -o zfsutil externaltest/nixos0/root /mnt; mkdir -p /mnt/home; mount -t zfs -o zfsutil externaltest/nixos0/data/home /mnt/home; mkdir -p /mnt/etc/zfs; cp /etc/zfs/zroot.key /mnt/etc/zfs/zroot.key")
    machine.succeed("nixos-install --root /mnt --system ${target} --no-root-passwd --no-channel-copy", timeout=300)
    p = json.loads(machine.succeed("${loader}/bin/zbm-rs --nixos-plans /mnt externaltest/nixos0/root ${imageConfig} ${target}"))[0]
    line = " ".join('"' + arg + '"' if any(c.isspace() for c in arg) else arg for arg in p["cmdline"])
    machine.succeed("kexec -l " + shlex.quote(p["kernel"]) + " --initrd=" + shlex.quote(p["initrd"]) + " --command-line=" + shlex.quote(line))
    machine.succeed("umount /mnt/home /mnt; zpool export externaltest")
    machine.execute("systemctl --no-block kexec", check_return=False)
    machine.connected = False
    machine.connect()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("test $(findmnt -n -o SOURCE /) = externaltest/nixos0/root; test $(findmnt -n -o SOURCE /home) = externaltest/nixos0/data/home; test $(findmnt -n -o SOURCE /home/okhsunrog/tmp_zfs) = externaltest/tmp_zfs_home; test $(findmnt -n -o SOURCE /home/okhsunrog/Nextcloud) = externaltest/nextcloud")
    for dataset in ["externaltest", "externaltest/nixos0/root", "externaltest/nixos0/data/home", "externaltest/nextcloud", "externaltest/tmp_zfs_home"]:
        machine.succeed(f"test $(zfs get -H -o value keystatus {dataset}) = available")
    machine.succeed("cryptsetup status nvme-swap")
    swaps = machine.succeed("cat /proc/swaps").splitlines()[1:]
    assert len(swaps) == 1, f"Expected the dedicated encrypted swap, got: {swaps}"
    device = shlex.quote(swaps[0].split()[0])
    machine.succeed(f"test $(stat -Lc %t:%T {device}) = $(stat -Lc %t:%T /dev/mapper/nvme-swap)")
    machine.fail("journalctl -b -u systemd-udevd.service --no-pager | grep 'Failed to find and pin callout binary'")
  '';
}
