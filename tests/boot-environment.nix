{ pkgs, module }:
let
  targetConfig =
    (import "${pkgs.path}/nixos/lib/eval-config.nix" {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        module
        "${pkgs.path}/nixos/modules/profiles/qemu-guest.nix"
        "${pkgs.path}/nixos/modules/testing/test-instrumentation.nix"
        {
          networking.hostName = "installed-be";
          networking.hostId = "00bab10c";
          boot.loader.zfsbootmenu = {
            enable = true;
            rootDataset = "testpool/nixos0/root";
            keyFile = "/etc/zfs/test.key";
          };
          boot.zfs.requestEncryptionCredentials = [ "testpool" ];
          # emptyDiskImages has no serial and therefore no by-id link.
          boot.zfs.devNodes = "/dev/disk/by-path";
          boot.kernelParams = [ "console=ttyS0" ];
          fileSystems."/" = {
            device = "testpool/nixos0/root";
            fsType = "zfs";
            options = [ "zfsutil" ];
          };
          fileSystems."/home" = {
            device = "testpool/nixos0/data/home";
            fsType = "zfs";
            options = [ "zfsutil" ];
            neededForBoot = true;
          };
          # Exercise account activation before switch-root, as on the laptop.
          users.users.probe = {
            isNormalUser = true;
            uid = 1000;
          };
          environment.systemPackages = [ pkgs.kexec-tools ];
          environment.etc."generation-marker".text = "original";
          specialisation.updated.configuration.environment.etc."generation-marker".text =
            pkgs.lib.mkForce "updated";
          system.stateVersion = "26.05";
        }
      ];
    }).config;
  target = targetConfig.system.build.toplevel;
in
pkgs.testers.runNixOSTest {
  name = "zfsbootmenu-boot-environment";
  globalTimeout = 300;
  nodes.machine = { ... }: {
    boot.supportedFilesystems = [ "zfs" ];
    networking.hostId = "00bab10c";
    virtualisation.memorySize = 2048;
    virtualisation.emptyDiskImages = [ 16000 ];
    environment.systemPackages = [
      pkgs.zfs
      pkgs.kexec-tools
      pkgs.nixos-install-tools
    ];
    virtualisation.additionalPaths = [ target ];
  };
  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("mkdir -p /etc/zfs; printf '%s' disposable-vm-password > /etc/zfs/test.key; chmod 600 /etc/zfs/test.key")
    machine.succeed("zpool create -O mountpoint=none -O overlay=off -O acltype=posixacl -O xattr=sa -O encryption=aes-256-gcm -O keyformat=passphrase -O keylocation=file:///etc/zfs/test.key testpool /dev/vdb")
    machine.succeed("zfs create -u -o mountpoint=none testpool/nixos0")
    machine.succeed("zfs create -u -o mountpoint=/ -o canmount=noauto testpool/nixos0/root")
    machine.succeed("zfs create -u -o mountpoint=none testpool/nixos0/data; zfs create -u -o mountpoint=/home -o canmount=noauto testpool/nixos0/data/home")
    machine.succeed("zfs create -u -o mountpoint=none testpool/foreign; zfs create -u -o mountpoint=/ -o canmount=noauto testpool/foreign/root; zfs create -u -o mountpoint=/foreign-home testpool/foreign/home")
    machine.succeed("mkdir -p /mnt; mount -t zfs -o zfsutil testpool/nixos0/root /mnt; mkdir /mnt/home; mount -t zfs -o zfsutil testpool/nixos0/data/home /mnt/home")
    machine.succeed("mkdir -p /mnt/etc/zfs; cp /etc/zfs/test.key /mnt/etc/zfs/test.key")
    status, output = machine.execute("nixos-install --root /mnt --system ${target} --no-root-passwd --no-channel-copy", timeout=300)
    if status != 0:
        print(output)
        print(machine.execute("nixos-enter --root /mnt --command '${pkgs.bash}/bin/bash -x ${targetConfig.system.build.installBootLoader} ${target}'"))
        raise Exception("nixos-install failed")
    machine.succeed("test -s /mnt/boot/vmlinuz-nixos; test -s /mnt/boot/initramfs-nixos.img; zfs snapshot testpool/nixos0/root@original")
    # Mimic ZBM's kexec handoff, including its dynamically chosen root.
    machine.succeed("kexec -l /mnt/boot/vmlinuz-nixos --initrd=/mnt/boot/initramfs-nixos.img --command-line='root=ZFS=testpool/nixos0/root init=/boot/nixos-current/system/init console=ttyS0 rw spl.spl_hostid=0x00bab10c'")
    machine.succeed("umount /mnt/home /mnt; zpool export testpool")
    machine.execute("systemctl --no-block kexec", check_return=False)
    machine.connected = False
    machine.connect()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("test $(findmnt -n -o SOURCE /) = testpool/nixos0/root; test $(hostid) = 00bab10c")
    machine.succeed("test $(cat /etc/generation-marker) = original; test $(findmnt -n -o SOURCE /home) = testpool/nixos0/data/home; ! findmnt /foreign-home")
    machine.succeed("test $(stat -c %u /home/probe) = 1000; test $(findmnt -n -o SOURCE -T /home/probe) = testpool/nixos0/data/home")
    # A plain bind mount exposes the root dataset without its child mounts.
    # Activation must not create a hidden home on the root before /home mounts.
    machine.succeed("mkdir -p /run/root-underlay; mount --bind / /run/root-underlay; test -z \"$(find /run/root-underlay/home -mindepth 1 -maxdepth 1 -print -quit)\"; umount /run/root-underlay")
    machine.succeed("readlink /boot/nixos-current > /tmp/bundle-before; mv /etc/zfs/test.key /etc/zfs/test.key.saved")
    machine.fail("${target}/specialisation/updated/bin/switch-to-configuration boot", timeout=120)
    machine.succeed("readlink /boot/nixos-current > /tmp/bundle-after; cmp /tmp/bundle-before /tmp/bundle-after; mv /etc/zfs/test.key.saved /etc/zfs/test.key")
    machine.succeed("${target}/specialisation/updated/bin/switch-to-configuration boot", timeout=120)
    machine.succeed("zfs clone -o mountpoint=/ -o canmount=noauto testpool/nixos0/root@original testpool/nixos0/recovery")
    machine.succeed("kexec -l /boot/vmlinuz-nixos --initrd=/boot/initramfs-nixos.img --command-line='root=ZFS=testpool/nixos0/root init=/boot/nixos-current/system/init console=ttyS0 rw spl.spl_hostid=0x00bab10c'")
    machine.execute("systemctl --no-block kexec", check_return=False)
    machine.connected = False
    machine.connect()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("test $(cat /etc/generation-marker) = updated")
    machine.succeed("mkdir -p /mnt/recovery; mount -t zfs -o zfsutil testpool/nixos0/recovery /mnt/recovery")
    machine.succeed("kexec -l /mnt/recovery/boot/vmlinuz-nixos --initrd=/mnt/recovery/boot/initramfs-nixos.img --command-line='root=ZFS=testpool/nixos0/recovery init=/boot/nixos-current/system/init console=ttyS0 rw spl.spl_hostid=0x00bab10c'")
    machine.succeed("umount /mnt/recovery")
    machine.execute("systemctl --no-block kexec", check_return=False)
    machine.connected = False
    machine.connect()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("test $(findmnt -n -o SOURCE /) = testpool/nixos0/recovery; test $(cat /etc/generation-marker) = original")
    machine.succeed("test $(findmnt -n -o SOURCE /home) = testpool/nixos0/data/home; ! findmnt /foreign-home")
    machine.succeed("${target}/specialisation/updated/bin/switch-to-configuration boot", timeout=120)
    machine.succeed("test $(zfs get -H -o value org.zfsbootmenu:keysource testpool/nixos0/recovery) = testpool/nixos0/recovery")
    machine.shutdown()
  '';
}
