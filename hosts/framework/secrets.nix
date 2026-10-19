{ host-secrets, ... }:
{
  imports = [
    (import ../../modules/secrets.nix {
      user = "okhsunrog";
      sopsFile = "${host-secrets}/framework.enc.json";
    })
  ];
}
