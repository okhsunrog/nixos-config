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
        ../modules/framework-environments
        "${nixpkgs}/nixos/modules/profiles/qemu-guest.nix"
        "${nixpkgs}/nixos/modules/testing/test-instrumentation.nix"
        {
          networking.hostName = "home-environments";
          networking.hostId = "00bab10c";
          boot.loader.zbm-rs.enable = true;
          boot.initrd.secrets."/etc/zfs/test.key" = "/etc/zfs/test.key";
          boot.initrd.systemd.services.zfs-import-testpool = {
            requires = [ "initrd-nixos-copy-secrets.service" ];
            after = [ "initrd-nixos-copy-secrets.service" ];
          };
          boot.zfs.requestEncryptionCredentials = [ "testpool" ];
          boot.zfs.devNodes = "/dev/disk/by-path";
          boot.kernelParams = [ "console=ttyS0" ];
          fileSystems."/" = {
            device = "testpool/nixos/root";
            fsType = "zfs";
            options = [ "zfsutil" ];
          };
          fileSystems."/home/tester/Nextcloud" = {
            device = "testpool/shared";
            fsType = "zfs";
            options = [ "zfsutil" ];
          };
          fileSystems."/home/tester/tmp_zfs" = {
            device = "testpool/tmp";
            fsType = "zfs";
            options = [ "zfsutil" ];
          };
          users.users.tester = {
            isNormalUser = true;
            uid = 1000;
            group = "tester";
          };
          users.groups.tester.gid = 1000;
          framework.environments = {
            enable = true;
            user = "tester";
            uid = 1000;
            gid = 1000;
            entries = {
              kde = {
                dataset = "testpool/nixos/home";
                backup = "mira";
              };
              experiment = {
                dataset = "testpool/nixos/home-experiment";
              };
              empty = {
                enable = false;
                dataset = "testpool/nixos/home-empty";
              };
            };
            variants.experiment = {
              environment.etc.environment-marker.text = "experiment";
            };
          };
          environment.etc.environment-marker.text = pkgs.lib.mkDefault "kde";
          environment.systemPackages = [
            pkgs.kexec-tools
            pkgs.jq
            zbm-rs.packages.${system}.zbm-rs
          ];
          system.extraDependencies = [ imageConfig ];
          system.stateVersion = "26.05";
        }
      ];
    }).config.system.build.toplevel;
  loader = zbm-rs.packages.${system}.zbm-rs;
  imageConfig = pkgs.writeText "home-test-image-config" "{}";
in
pkgs.testers.runNixOSTest {
  name = "framework-home-environments";
  globalTimeout = 900;
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
      pkgs.jq
    ];
  };
  testScript = ''
    import json, shlex
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("mkdir -p /etc/zfs; printf disposable-test-only > /etc/zfs/test.key; chmod 600 /etc/zfs/test.key")
    machine.succeed("zpool create -O mountpoint=none -O overlay=off -O encryption=aes-256-gcm -O keyformat=passphrase -O keylocation=file:///etc/zfs/test.key testpool /dev/vdb")
    machine.succeed("zfs create -u -o mountpoint=none testpool/nixos; zfs create -u -o canmount=noauto -o mountpoint=/ testpool/nixos/root; zfs create -u -o canmount=noauto -o mountpoint=/home testpool/nixos/home; zfs create -u -o canmount=noauto -o mountpoint=/home/tester/Nextcloud testpool/shared; zfs create -u -o canmount=noauto -o mountpoint=/home/tester/tmp_zfs testpool/tmp")
    machine.succeed("mkdir /mnt; mount -t zfs -o zfsutil testpool/nixos/root /mnt; mkdir /mnt/home; mount -t zfs -o zfsutil testpool/nixos/home /mnt/home; mkdir -p /mnt/etc/zfs; cp /etc/zfs/test.key /mnt/etc/zfs/test.key")
    machine.succeed("mkdir -p /mnt/home/tester/code/{nixos-config,nixos-secrets} /mnt/home/tester/.config; echo main > /mnt/home/tester/.config/desktop; echo canonical > /mnt/home/tester/code/nixos-config/marker; echo ciphertext-fixture > /mnt/home/tester/code/nixos-secrets/marker; chown -R 1000:1000 /mnt/home/tester; zfs snapshot testpool/nixos/home@experiment")
    helper = "${target}/sw/bin/framework-home --manifest ${target}/etc/framework-environments.json"
    machine.succeed(helper + " create experiment --from testpool/nixos/home@experiment")
    machine.fail(helper + " create experiment --empty")
    machine.succeed(helper + " create empty --empty")
    machine.fail(helper + " create empty --empty")
    machine.succeed("mkdir /check; mount -t zfs -o zfsutil testpool/nixos/home-empty /check; test $(stat -c %u:%g /check/tester) = 1000:1000; test ! -e /check/tester/.config; umount /check")
    machine.succeed("test $(zfs get -H -o value origin testpool/nixos/home-experiment) = testpool/nixos/home@experiment")
    machine.succeed("nixos-install --root /mnt --system ${target} --no-root-passwd --no-channel-copy", timeout=300)
    def boot(system, root):
        p = json.loads(machine.succeed(f"${loader}/bin/zbm-rs --nixos-plans {root} testpool/nixos/root ${imageConfig} {system}"))[0]
        line = " ".join('"' + arg + '"' if any(c.isspace() for c in arg) else arg for arg in p["cmdline"])
        machine.succeed("kexec -l " + shlex.quote(p["kernel"]) + " --initrd=" + shlex.quote(p["initrd"]) + " --command-line=" + shlex.quote(line))
        if root == "/mnt":
            machine.succeed("umount /mnt/home /mnt; zpool export testpool")
        machine.execute("systemctl --no-block kexec", check_return=False)
        machine.connected = False
        machine.connect()
        machine.wait_for_unit("multi-user.target")
    boot("${target}", "/mnt")
    machine.succeed("test $(cat /etc/environment-marker) = kde; test $(findmnt -n -o SOURCE --mountpoint /home) = testpool/nixos/home; framework-home preflight --action switch")
    status = machine.succeed("framework-home status")
    assert "specialisation/experiment" in status
    assert "testpool/nixos/home@experiment" in status
    machine.succeed("echo shared > /home/tester/Nextcloud/marker; echo tmp-shared > /home/tester/tmp_zfs/marker; echo main-later > /home/tester/.config/desktop")
    boot("${target}/specialisation/experiment", "/")
    machine.succeed("test $(cat /etc/environment-marker) = experiment; test $(findmnt -n -o SOURCE --mountpoint /home) = testpool/nixos/home-experiment; test $(cat /home/tester/.config/desktop) = main; test $(cat /home/tester/Nextcloud/marker) = shared; test $(cat /home/tester/tmp_zfs/marker) = tmp-shared; framework-home preflight --action switch")
    machine.succeed("test $(cat /home/tester/code/nixos-config/marker) = canonical; echo shared-edit > /home/tester/code/nixos-config/marker; echo experiment > /home/tester/.config/desktop")
    machine.fail(helper + " preflight --action switch")
    boot("${target}", "/")
    machine.succeed("test $(cat /home/tester/.config/desktop) = main-later; test $(cat /home/tester/code/nixos-config/marker) = shared-edit; framework-home preflight --action switch")
    machine.fail("journalctl -b --no-pager | grep 'Duplicate entry'")
    machine.shutdown()
  '';
}
