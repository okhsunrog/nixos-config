{ pkgs, zbm-rs }:
let
  fixture = import ./module-signing-fixture.nix { inherit pkgs zbm-rs; };
in
pkgs.testers.runNixOSTest {
  name = "framework-module-signing";
  nodes.machine = {
    virtualisation.writableStore = true;
    environment.systemPackages = [ fixture ];
  };
  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("framework-signing-integration", timeout=120)
  '';
}
