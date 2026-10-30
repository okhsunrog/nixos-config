{
  pkgs,
  nixpkgs,
  home-manager,
  zbm-rs,
  system,
}:
let
  makeTarget =
    shared:
    (import "${nixpkgs}/nixos/lib/eval-config.nix" {
      inherit system;
      modules = [
        home-manager.nixosModules.home-manager
        zbm-rs.nixosModules.default
        ../modules/framework-environments
        ../modules/zfs-udev-initrd.nix
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
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          programs.dconf.enable = true;
          home-manager.users = pkgs.lib.optionalAttrs shared {
            tester = {
              home.username = "tester";
              home.homeDirectory = "/home/tester";
              home.stateVersion = "26.05";
            };
          };
          framework.environments = {
            enable = true;
            user = "tester";
            uid = 1000;
            gid = 1000;
            homeMode = if shared then "shared" else "separate";
            configProfiles = pkgs.lib.mkIf shared {
              enable = true;
              mutableFiles = [ ".config/desktop" ];
              bindDirectories = [ ".config/desktop-dir" ];
              dconfKeys = [ "/org/gnome/desktop/interface/color-scheme" ];
            };
            entries = {
              kde = {
                dataset = "testpool/nixos/home";
                backup = "mira";
              };
              experiment = {
                dataset = if shared then "testpool/nixos/home" else "testpool/nixos/home-experiment";
                backup = if shared then "mira" else "local";
              };
              empty = {
                enable = false;
                dataset = "testpool/nixos/home-empty";
              };
            };
            variants.experiment = {
              environment.etc.environment-marker.text = "experiment";
              home-manager.users.tester = {
                home.username = "tester";
                home.homeDirectory = "/home/tester";
                home.stateVersion = "26.05";
                xdg.configFile."home-manager-environment".text = "experiment-only";
              };
            };
          };
          environment.etc.environment-marker.text = pkgs.lib.mkDefault "kde";
          environment.systemPackages = [
            pkgs.kexec-tools
            pkgs.jq
            zbm-rs.packages.${system}.zbm-rs
          ];
          system.extraDependencies = [ imageConfig ] ++ pkgs.lib.optional (!shared) sharedTarget;
          system.stateVersion = "26.05";
        }
      ];
    }).config.system.build.toplevel;
  target = makeTarget false;
  sharedTarget = makeTarget true;
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
    virtualisation.additionalPaths = [
      target
      sharedTarget
    ];
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
        machine.fail("journalctl -b -u systemd-udevd.service --no-pager | grep 'Failed to find and pin callout binary'")
    boot("${target}", "/mnt")
    machine.succeed("test $(cat /etc/environment-marker) = kde; test $(findmnt -n -o SOURCE --mountpoint /home) = testpool/nixos/home; framework-home preflight --action switch")
    status = machine.succeed("framework-home status")
    assert "specialisation/experiment" in status
    assert "testpool/nixos/home@experiment" in status
    machine.succeed("echo shared > /home/tester/Nextcloud/marker; echo tmp-shared > /home/tester/tmp_zfs/marker; echo main-later > /home/tester/.config/desktop")
    boot("${target}/specialisation/experiment", "/")
    machine.wait_for_unit("home-manager-tester.service")
    machine.succeed("test $(cat /home/tester/.config/home-manager-environment) = experiment-only; test ! -e /var/lib/framework-environments/primary-home/tester/.config/home-manager-environment")
    machine.succeed("test $(cat /etc/environment-marker) = experiment; test $(findmnt -n -o SOURCE --mountpoint /home) = testpool/nixos/home-experiment; test $(cat /home/tester/.config/desktop) = main; test $(cat /home/tester/Nextcloud/marker) = shared; test $(cat /home/tester/tmp_zfs/marker) = tmp-shared; framework-home preflight --action switch")
    machine.succeed("test $(cat /home/tester/code/nixos-config/marker) = canonical; echo shared-edit > /home/tester/code/nixos-config/marker; echo experiment > /home/tester/.config/desktop")
    machine.fail(helper + " preflight --action switch")
    boot("${target}", "/")
    machine.succeed("test ! -e /home/tester/.config/home-manager-environment; test $(cat /home/tester/.config/desktop) = main-later; test $(cat /home/tester/code/nixos-config/marker) = shared-edit; framework-home preflight --action switch")
    machine.fail("journalctl -b --no-pager | grep 'Duplicate entry'")
    shared_helper = "${sharedTarget}/sw/bin/framework-home --manifest ${sharedTarget}/etc/framework-environments.json"
    machine.succeed("mkdir -p /source /home/tester/.config/desktop-dir; echo kde-dir > /home/tester/.config/desktop-dir/value; mount -t zfs -o zfsutil testpool/nixos/home-experiment /source; mkdir -p /source/tester/.config/desktop-dir; echo niri-dir > /source/tester/.config/desktop-dir/value")
    machine.succeed(shared_helper + " prepare-profiles --source kde=/home/tester --source experiment=/source/tester")
    machine.succeed("test ! -e /home/.desktop-profiles/tester/state.json")
    machine.succeed(shared_helper + " prepare-profiles --source kde=/home/tester --source experiment=/source/tester --apply")
    machine.succeed("umount /source")
    machine.fail(shared_helper + " preflight --action switch")
    machine.succeed(shared_helper + " preflight --action boot")
    machine.succeed("nix-env --profile /nix/var/nix/profiles/system --set ${sharedTarget}; ${sharedTarget}/bin/switch-to-configuration boot", timeout=120)
    boot("${sharedTarget}", "/")
    machine.wait_for_unit("home-manager-tester.service")
    machine.succeed("test $(findmnt -n -o SOURCE --mountpoint /home) = testpool/nixos/home; test $(cat /home/tester/.config/desktop-dir/value) = kde-dir; framework-home preflight --action switch")
    machine.succeed("systemctl start user@1000.service; systemctl is-active --quiet user@1000.service")
    machine.fail("framework-home activate-profile")
    machine.succeed("${sharedTarget}/bin/switch-to-configuration test", timeout=120)
    machine.succeed("echo shared-app > /home/tester/.config/ordinary-application; echo shared-bookmark > /home/tester/.config/bookmarks")
    machine.fail("${sharedTarget}/specialisation/experiment/bin/switch-to-configuration test")
    boot("${sharedTarget}/specialisation/experiment", "/")
    machine.wait_for_unit("home-manager-tester.service")
    machine.succeed("test $(cat /home/tester/.config/desktop) = experiment; test $(cat /home/tester/.config/desktop-dir/value) = niri-dir; test $(cat /home/tester/.config/ordinary-application) = shared-app; test $(cat /home/tester/.config/bookmarks) = shared-bookmark; test $(cat /home/tester/Nextcloud/marker) = shared; test $(cat /home/tester/tmp_zfs/marker) = tmp-shared; framework-home preflight --action switch")
    machine.succeed("test $(findmnt -n -o SOURCE --mountpoint /home) = testpool/nixos/home; ! mountpoint -q /var/lib/framework-environments/primary-home; test $(cat /home/tester/.config/home-manager-environment) = experiment-only; printf niri-edited > /home/tester/.config/desktop.new; mv /home/tester/.config/desktop.new /home/tester/.config/desktop")
    machine.fail(shared_helper + " preflight --action switch")
    boot("${sharedTarget}", "/")
    machine.wait_for_unit("home-manager-tester.service")
    machine.succeed("test $(cat /home/tester/.config/desktop) = main-later; test $(cat /home/tester/.config/desktop-dir/value) = kde-dir; test ! -e /home/tester/.config/home-manager-environment; test $(cat /home/tester/.config/ordinary-application) = shared-app; framework-home preflight --action switch")
    boot("${sharedTarget}/specialisation/experiment", "/")
    machine.wait_for_unit("home-manager-tester.service")
    machine.succeed("test $(cat /home/tester/.config/desktop) = niri-edited; framework-home preflight --action switch")
    # Fail closed if a required prepared profile is unavailable.
    machine.succeed("mv /home/.desktop-profiles/tester/experiment/files.json /home/.desktop-profiles/tester/experiment/files.missing")
    machine.fail(shared_helper + " preflight --action boot")
    boot("${sharedTarget}", "/")
    machine.fail("systemctl is-active --quiet framework-desktop-profile.service")
    machine.fail("systemctl is-active --quiet systemd-user-sessions.service")
    machine.fail("systemctl is-active --quiet home-manager-tester.service")
    machine.fail("systemctl start user@1000.service")
    machine.succeed("mv /home/.desktop-profiles/tester/experiment/files.missing /home/.desktop-profiles/tester/experiment/files.json")
    machine.succeed("systemctl start framework-desktop-profile.service home-manager-tester.service systemd-user-sessions.service")
    machine.shutdown()
  '';
}
