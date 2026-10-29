{ pkgs, framework }:
let
  lib = pkgs.lib;
  kde = framework.config;
  preview = framework.extendModules {
    modules = [ ({ lib, ... }: { framework.environments.entries.niri.enable = lib.mkForce true; }) ];
  };
  niri = preview.config.specialisation.niri.configuration;
  fingerprint = pkgs.writeShellScript "test-fingerprint" ''
    ${pkgs.coreutils}/bin/touch /run/fingerprint-requested
    test -e /run/fingerprint-accepted
  '';
  # Test the actual host-generated PAM stacks. Only the physical fingerprint
  # module is replaced; passwords still go through real pam_unix in the VM.
  pamService = cfg: name: {
    text = lib.mkForce (
      builtins.replaceStrings
        [ "${cfg.services.fprintd.package}/lib/security/pam_fprintd.so" ]
        [ "${pkgs.pam}/lib/security/pam_exec.so quiet ${fingerprint}" ]
        cfg.security.pam.services.${name}.text
    );
  };
in
pkgs.testers.runNixOSTest {
  name = "desktop-password-login-independent-unlock";
  nodes.machine = {
    users.users.tester = {
      isNormalUser = true;
      initialPassword = "test-only-password";
    };
    environment.systemPackages = [ pkgs.pamtester ];
    security.pam.services =
      lib.genAttrs [ "login" "plasmalogin" "plasmalogin-auth" "kde" "kde-fingerprint" ] (pamService kde)
      // lib.genAttrs [ "greetd" "greetd-password" "dankshell" ] (pamService niri);
  };
  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    # Even an accepted fingerprint cannot bypass a greeter's password or run
    # as a second prompt after a correct password.
    machine.succeed("touch /run/fingerprint-accepted")
    for service in ["plasmalogin", "greetd", "kde", "dankshell"]:
        with subtest(f"{service}: password succeeds independently"):
            machine.succeed(f"printf '%s\\n' test-only-password | pamtester {service} tester authenticate acct_mgmt")
            machine.succeed("test ! -e /run/fingerprint-requested")
        with subtest(f"{service}: invalid and blank passwords fail"):
            machine.fail(f"printf '%s\\n' incorrect | pamtester {service} tester authenticate")
            machine.fail(f"printf '\\n' | pamtester {service} tester authenticate")
            machine.succeed("test ! -e /run/fingerprint-requested")

    with subtest("fingerprint unlock succeeds without a password"):
        machine.succeed("pamtester kde-fingerprint tester authenticate acct_mgmt </dev/null")
        machine.succeed("test -e /run/fingerprint-requested")
        machine.succeed("rm /run/fingerprint-requested /run/fingerprint-accepted")

    with subtest("failed fingerprint cannot fall through to password"):
        machine.fail("printf '%s\\n' test-only-password | pamtester kde-fingerprint tester authenticate")
        machine.succeed("test -e /run/fingerprint-requested")

    with subtest("password still unlocks after a failed fingerprint"):
        machine.succeed("printf '%s\\n' test-only-password | pamtester kde tester authenticate acct_mgmt")
  '';
}
