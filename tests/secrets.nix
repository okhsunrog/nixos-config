{ pkgs, sops-nix }:
pkgs.testers.runNixOSTest {
  name = "framework-sops";
  nodes.machine = { config, pkgs, ... }: {
    imports = [ sops-nix.nixosModules.sops ];
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
          printf '{"password":"%s","credential":"test-only-credential"}' "$hash" |
            ${pkgs.sops}/bin/sops encrypt --age "$recipient" --input-type json --output-type json /dev/stdin > /var/lib/sops-nix/test.enc.json
        fi
      '';
    };
    system.activationScripts.setupSecretsForUsers.deps = [ "testSopsBootstrap" ];
    sops = {
      defaultSopsFile = "/var/lib/sops-nix/test.enc.json";
      defaultSopsFormat = "json";
      validateSopsFiles = false;
      age.keyFile = "/var/lib/sops-nix/key.txt";
      age.sshKeyPaths = [ ];
      gnupg.sshKeyPaths = [ ];
      useSystemdActivation = true;
      secrets.password.neededForUsers = true;
      secrets.credential.mode = "0600";
    };
    users.users.test-user = {
      isNormalUser = true;
      hashedPasswordFile = config.sops.secrets.password.path;
    };
  };
  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("sops-install-secrets.service")
    machine.succeed("test $(stat -c %a /var/lib/sops-nix/key.txt) = 0")
    machine.succeed("test \"$(getent shadow test-user | cut -d: -f2)\" = \"$(cat /run/secrets-for-users/password)\"")
    machine.succeed("test $(cat /run/secrets/credential) = test-only-credential")
    machine.succeed("test $(findmnt -n -o FSTYPE --target /run/secrets/credential) = ramfs")
    machine.fail("su -s /bin/sh test-user -c 'cat /var/lib/sops-nix/key.txt'")
    machine.fail("su -s /bin/sh test-user -c 'cat /run/secrets/credential'")
  '';
}
