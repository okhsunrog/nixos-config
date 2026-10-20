{ pkgs }:
pkgs.testers.runNixOSTest {
  name = "plasma-login-password-first";
  nodes.machine =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ ../modules/plasma-login-auth.nix ];
      users.users.tester = {
        isNormalUser = true;
        initialPassword = "test-only-password";
      };
      environment.systemPackages = [ pkgs.pamtester ];
      security.pam.services = {
        login.kwallet.enable = true;
        # Match the upstream greeter's substack without starting a desktop.
        plasmalogin = {
          useDefaultRules = false;
          rules.auth.login = {
            order = 10100;
            control = "substack";
            modulePath = "login";
          };
          rules.account.login = {
            order = 10100;
            control = "include";
            modulePath = "login";
          };
        };
        plasmalogin-auth = {
          fprintAuth = true;
          # Test-only fingerprint result. Real pam_unix still verifies the
          # disposable user's password, and the production ordering is retained.
          rules.auth.fprintd = {
            modulePath = lib.mkForce "${config.security.pam.package}/lib/security/pam_exec.so";
            args = [
              "quiet"
              (toString (
                pkgs.writeShellScript "test-fingerprint" ''
                  ${pkgs.coreutils}/bin/touch /run/fingerprint-requested
                  test -e /run/fingerprint-accepted
                ''
              ))
            ];
          };
        };
      };
    };
  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("grep -F 'auth substack plasmalogin-auth' /etc/pam.d/plasmalogin")

    # A valid password succeeds even when the fingerprint would fail.
    machine.succeed("printf '%s\\n' test-only-password | pamtester plasmalogin tester authenticate acct_mgmt")
    machine.succeed("test ! -e /run/fingerprint-requested")

    # Failed password plus failed fingerprint must not admit the user.
    machine.fail("printf '%s\\n' incorrect | pamtester plasmalogin tester authenticate")
    machine.succeed("test -e /run/fingerprint-requested")
    machine.succeed("rm /run/fingerprint-requested")

    # Blank input can use the fingerprint fallback; it is not a second factor.
    machine.succeed("touch /run/fingerprint-accepted")
    machine.succeed("printf '\\n' | pamtester plasmalogin tester authenticate acct_mgmt")
    machine.succeed("test -e /run/fingerprint-requested")

    # Blank input by itself must still be rejected.
    machine.succeed("rm /run/fingerprint-accepted")
    machine.fail("printf '\\n' | pamtester plasmalogin tester authenticate")
  '';
}
