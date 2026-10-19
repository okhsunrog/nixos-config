{
  config,
  host-secrets,
  ...
}:
{
  services.arctern = {
    enable = true;
    configFile = "/etc/arctern/arctern.toml";
  };
  environment.etc."arctern/arctern.toml".source = ./arctern.toml;

  sops.secrets.arctern-ssh-key = {
    sopsFile = "${host-secrets}/arctern-ssh-key.enc";
    format = "binary";
    path = "/var/lib/arctern/ssh/id_ed25519";
    mode = "0600";
    restartUnits = [ "arctern.service" ];
  };
  systemd.tmpfiles.rules = [
    "d /var/lib/arctern 0700 root root -"
    "d /var/lib/arctern/ssh 0700 root root -"
  ];
  systemd.services.arctern = {
    requires = [ "sops-install-secrets.service" ];
    after = [ "sops-install-secrets.service" ];
    restartTriggers = [ ./arctern.toml ];
    unitConfig.ConditionPathExists = config.sops.secrets.arctern-ssh-key.path;
  };
  programs.ssh.extraConfig = ''
    Host arctern-mira-lan
      HostName 10.77.77.100
      User root
      IdentityFile /var/lib/arctern/ssh/id_ed25519
      IdentitiesOnly yes
    Host arctern-mira-wg
      HostName 10.66.66.2
      User root
      IdentityFile /var/lib/arctern/ssh/id_ed25519
      IdentitiesOnly yes
  '';
}
