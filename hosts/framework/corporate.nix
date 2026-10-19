{ config, ... }: {
  imports = [ ../../modules/corporate ];
  services.corporate-workstation = {
    enable = true;
    user = "okhsunrog";
    orbitEnvironmentFile = config.sops.secrets.orbit-environment.path;
  };
  systemd.services.orbit = {
    requires = [ "sops-install-secrets.service" ];
    after = [ "sops-install-secrets.service" ];
  };
}
