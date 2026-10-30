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
            nextcloud = false;
            portable = true;
            tmpDataset = "externaltest/nixos0/data/home/tmp_zfs";
            encryptionRoots = [
              "externaltest/nixos0/root"
              "externaltest/nixos0/data/home"
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
    virtualisation.emptyDiskImages = [ 16000 ];
    virtualisation.additionalPaths = [ target ];
    environment.systemPackages = [
      pkgs.zfs
      pkgs.kexec-tools
      pkgs.nixos-install-tools
    ];
  };
  testScript = ''
    import json, shlex
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("mkdir -p /etc/zfs; printf disposable-test-only > /etc/zfs/zroot.key; chmod 600 /etc/zfs/zroot.key")
    machine.succeed("zpool create -O mountpoint=none externaltest /dev/vdb; zfs create -p -o mountpoint=none externaltest/nixos0/data")
    for dataset, mountpoint in [("externaltest/nixos0/root", "/"), ("externaltest/nixos0/data/home", "/home")]:
        machine.succeed(f"zfs create -o encryption=aes-256-gcm -o keyformat=passphrase -o keylocation=file:///etc/zfs/zroot.key -o canmount=noauto -o mountpoint={mountpoint} {dataset}")
    machine.succeed("zfs create -o canmount=noauto -o mountpoint=/home/okhsunrog/tmp_zfs externaltest/nixos0/data/home/tmp_zfs")
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
    machine.succeed("test $(findmnt -n -o SOURCE /) = externaltest/nixos0/root; test $(findmnt -n -o SOURCE /home) = externaltest/nixos0/data/home; test $(findmnt -n -o SOURCE /home/okhsunrog/tmp_zfs) = externaltest/nixos0/data/home/tmp_zfs")
    machine.succeed("test $(zfs get -H -o value keystatus externaltest/nixos0/root) = available; test $(zfs get -H -o value keystatus externaltest/nixos0/data/home) = available")
    machine.fail("journalctl -b -u systemd-udevd.service --no-pager | grep 'Failed to find and pin callout binary'")
  '';
}
