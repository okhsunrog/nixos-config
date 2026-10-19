{ pkgs }:
let
  corporate = import ../packages/corporate.nix { inherit pkgs; };
  # No enrollment, remote task or real credential is used in this VM.
  sleeper = pkgs.writeShellScript "disposable-agent" ''
    # The vendor NAC resolves the desktop user's home through getent at startup.
    # Keep this lookup in the service's PATH, matching the real agent contract.
    getent passwd tester >/dev/null || exit 1
    exec ${pkgs.coreutils}/bin/sleep infinity
  '';
  nacSleeper = pkgs.writeShellScript "disposable-nac" ''
    kreadconfig6 --version >/dev/null || exit 1
    exec ${sleeper}
  '';
  dummy = pkgs.runCommand "disposable-agents" { } ''
    mkdir -p $out/bin $out/libexec/fleet-orbit
    for name in nac-agent orbit osqueryd; do ln -s ${sleeper} $out/bin/$name; done
    ln -sfn ${nacSleeper} $out/bin/nac-agent
    touch $out/libexec/fleet-orbit/{certs.pem,osquery.flags,tuf-metadata.json}
  '';
  scriptProbe = pkgs.writeShellScript "corporate-archive-probe" ''
    set -e
    directory=$(${pkgs.coreutils}/bin/mktemp -d /var/lib/corporate-agent-work/orbit/fleet-vm-XXXXXX)
    printf '#!/bin/sh\nprintf archive-proof\\n\n' > "$directory/script"
    ${pkgs.bash}/bin/bash "$directory/script"
    ${pkgs.coreutils}/bin/rm -r "$directory"
  '';
  denyProbe = pkgs.writeShellScript "corporate-deny-probe" ''
    set -e
    for path in /mnt/nfs/private /home/tester/private /var/lib/sops-nix/key.txt /etc/zfs/zroot.key /root/.netrc; do
      if ${pkgs.coreutils}/bin/cat "$path"; then exit 1; fi
    done
    if ${pkgs.coreutils}/bin/touch /etc/corporate-write-probe; then exit 1; fi
  '';
in
pkgs.testers.runNixOSTest {
  name = "corporate-workstation";
  nodes.machine = { config, lib, ... }: {
    imports = [ ../modules/corporate ];
    virtualisation = {
      memorySize = 2048;
      tpm.enable = true;
      useEFIBoot = true;
      fileSystems."/var/lib/corporate-agent-work" = import ../modules/corporate/work-filesystem.nix;
    };
    users.users.tester = {
      isNormalUser = true;
      uid = 1000;
      linger = true;
    };
    security.lsm = lib.mkForce [
      "landlock"
      "lockdown"
      "yama"
      "apparmor"
      "bpf"
    ];
    services.corporate-workstation = {
      enable = true;
      user = "tester";
      packages = corporate // {
        nac-agent = dummy;
        fleet-orbit = dummy;
      };
    };
    system.activationScripts.testCorporateState.text = ''
      install -d /mnt/nfs /home/tester /etc/zfs /var/lib/sops-nix
      for path in /mnt/nfs/private /home/tester/private /etc/zfs/zroot.key /var/lib/sops-nix/key.txt /root/.netrc; do
        echo disposable-private-data > "$path"
      done
      install -d -m0700 /run/secrets
      echo 'CORPORATE_TEST_ENV=disposable' > /run/secrets/orbit-environment
      chmod 600 /run/secrets/orbit-environment
    '';
    environment.systemPackages = [
      pkgs.python3
      pkgs.libcap
      pkgs.jq
      pkgs.apparmor-bin-utils
    ];
  };
  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    print(machine.succeed("systemctl --failed; journalctl -b -u orbit -u nac-agent -u agent-script-archive --no-pager"))
    for unit in ("apparmor", "auditd", "audit-rules-nixos", "agent-script-archive", "corporate-agent-dbus", "nac-agent", "orbit", "firewalld", "systemd-resolved", "tpm2-abrmd"):
        machine.wait_for_unit(unit + ".service")
    machine.wait_for_unit("user@1000.service")
    # A signed Orbit update moves the program links away from the seed cache.
    # Restarting the service must preserve both updater-managed selections.
    for program in ("orbit", "osqueryd"):
        machine.succeed(f"mkdir -p /opt/orbit/bin/{program}/linux/updated; cp -L /opt/orbit/bin/{program}/{program} /opt/orbit/bin/{program}/linux/updated/{program}; ln -sfn linux/updated/{program} /opt/orbit/bin/{program}/{program}")
    machine.succeed("systemctl restart orbit")
    machine.wait_for_unit("orbit.service")
    for program in ("orbit", "osqueryd"):
        machine.succeed(f"test $(readlink /opt/orbit/bin/{program}/{program}) = linux/updated/{program}")
    user = "runuser -u tester -- env XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus "
    machine.succeed(user + "systemctl --user start vkey-runtime-setup")
    machine.succeed(user + "tpm2_getrandom 4 >/dev/null")
    machine.succeed(user + "python3 -c \"import ctypes; ctypes.CDLL('/home/tester/.local/share/vkey-x509/libtpm2-pkcs11.so')\"")
    machine.succeed("grep 'name=vkey-x509' /home/tester/.pki/nssdb/pkcs11.txt")
    machine.succeed(user + "/run/wrappers/bin/vkey-openvpn --mktun --dev tun-cap-test")
    machine.succeed(user + "/run/wrappers/bin/vkey-openvpn --rmtun --dev tun-cap-test")
    machine.succeed("test \"$(cat /proc/$(systemctl show -p MainPID --value orbit)/attr/current)\" = 'corporate-orbit (enforce)'")
    machine.succeed("pid=$(systemctl show -p MainPID --value orbit); grep -zq CORPORATE_TEST_ENV=disposable /proc/$pid/environ; nsenter -t $pid -m -- /bin/bash -c 'test -x /usr/bin/python3 && ! cat /run/secrets/orbit-environment'")
    for profile in ("corporate-orbit", "corporate-nac"):
        machine.succeed(f"systemd-run --wait --pipe -p AppArmorProfile={profile} ${denyProbe}")
    machine.succeed("systemd-run --wait --pipe -p AppArmorProfile=corporate-orbit ${scriptProbe}")
    machine.succeed("agent-audit list | grep fleet-vm")
    machine.succeed("agent-audit commands | grep corporate-archive-probe")
    machine.succeed("pid=$(systemctl show -p MainPID --value orbit); nsenter -t $pid -m -- sh -c '! grep -q disposable-private-data /mnt/nfs/private && ! grep -q disposable-private-data /etc/zfs/zroot.key'")
    # Filtered D-Bus permits facts, rejects host mutations.
    bus = "busctl --address=unix:path=/run/corporate-agent-dbus/system-bus "
    machine.succeed(bus + "get-property org.freedesktop.hostname1 /org/freedesktop/hostname1 org.freedesktop.hostname1 Hostname")
    machine.fail(bus + "call org.freedesktop.hostname1 /org/freedesktop/hostname1 org.freedesktop.hostname1 SetHostname sb forbidden false")
    # DNS is set on this tunnel only; removal clears its link-scoped settings.
    machine.succeed("ip link add corp-dns-test type dummy; ip link set corp-dns-test up")
    print(machine.succeed("sudo -l -U tester"))
    machine.succeed(user + "env foreign_option_1='dhcp-option DNS 172.21.0.1' foreign_option_2='dhcp-option DOMAIN vk.team' /home/tester/.local/share/vkey-x509/barbos.ovpn.sh corp-dns-test")
    machine.succeed("resolvectl domain corp-dns-test | grep '~vk.team'")
    machine.succeed("resolvectl default-route corp-dns-test | grep no")
    machine.succeed("resolvectl dns corp-dns-test | grep 172.21.0.1")
    machine.fail("resolvectl domain corp-dns-test | grep -E '~\\.( |$)'")
    machine.succeed("ip link del corp-dns-test")
    machine.fail("resolvectl status corp-dns-test")
    # Guard failures stop dependents instead of leaving unobserved agents.
    machine.succeed("systemctl stop agent-script-archive")
    machine.wait_until_fails("systemctl is-active orbit nac-agent")
  '';
}
