{ pkgs, sops-nix }:
pkgs.testers.runNixOSTest {
  name = "framework-sops";
  nodes.machine = { pkgs, ... }: {
    imports = [
      sops-nix.nixosModules.sops
      (import ../modules/secrets.nix {
        user = "tester";
        sopsFile = "/var/lib/sops-nix/test.enc.json";
      })
    ];
    # Disposable test-only material is generated inside the guest. No real
    # host key, password hash, Forgejo credential or encrypted vault is used.
    system.activationScripts.testSopsBootstrap = {
      deps = [ "specialfs" ];
      text = ''
        install -d -m700 /var/lib/sops-nix
        if [ ! -s /var/lib/sops-nix/key.txt ]; then
          ${pkgs.age}/bin/age-keygen -o /var/lib/sops-nix/key.txt
          chmod 000 /var/lib/sops-nix/key.txt
          recipient=$(${pkgs.age}/bin/age-keygen -y /var/lib/sops-nix/key.txt)
          hash=$(${pkgs.openssl}/bin/openssl passwd -6 test-only-password)
          printf '{"root-password-hash":"%s","tester-password-hash":"%s","forgejo-netrc":"test-only-credential","orbit-environment":"ORBIT_TEST=disposable"}' "$hash" "$hash" |
            ${pkgs.sops}/bin/sops encrypt --age "$recipient" --input-type json --output-type json /dev/stdin > /var/lib/sops-nix/test.enc.json
        fi
      '';
    };
    system.activationScripts.setupSecretsForUsers.deps = [ "testSopsBootstrap" ];
    sops.validateSopsFiles = false;
    users.users.tester.isNormalUser = true;
  };
  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("sops-install-secrets.service")
    machine.succeed("systemctl start nix-daemon.service")
    machine.wait_for_unit("nix-daemon.service")
    for property in ("After", "Requires"):
        assert "sops-install-secrets.service" in machine.succeed(f"systemctl show nix-daemon -p {property} --value").split()
    machine.succeed("test $(readlink -f /root/.netrc) = $(readlink -f /run/secrets/forgejo-netrc)")
    machine.succeed("grep -Fx 'netrc-file = /root/.netrc' /etc/nix/nix.conf")
    machine.succeed("test $(stat -Lc %a /root/.netrc) = 600")
    machine.succeed("test $(stat -c %a /var/lib/sops-nix) = 700")
    machine.succeed("test $(cat /run/secrets/orbit-environment) = ORBIT_TEST=disposable")
    machine.succeed("test $(stat -c %a /var/lib/sops-nix/key.txt) = 0")
    machine.succeed("test \"$(getent shadow tester | cut -d: -f2)\" = \"$(cat /run/secrets-for-users/tester-password-hash)\"")
    machine.succeed("test $(cat /run/secrets/forgejo-netrc) = test-only-credential")
    machine.succeed("test $(findmnt -n -o FSTYPE --target /run/secrets/forgejo-netrc) = ramfs")
    machine.fail("su -s /bin/sh tester -c 'cat /var/lib/sops-nix/key.txt'")
    machine.fail("su -s /bin/sh tester -c 'cat /run/secrets/forgejo-netrc'")
  '';
}
