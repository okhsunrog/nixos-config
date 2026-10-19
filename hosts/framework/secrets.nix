{
  config,
  pkgs,
  host-secrets,
  ...
}:
{
  sops = {
    defaultSopsFile = "${host-secrets}/framework.enc.json";
    defaultSopsFormat = "json";
    age = {
      keyFile = "/var/lib/sops-nix/key.txt";
      generateKey = false;
      sshKeyPaths = [ ];
    };
    gnupg.sshKeyPaths = [ ];
    useSystemdActivation = true;
    secrets = {
      root-password-hash.neededForUsers = true;
      okhsunrog-password-hash.neededForUsers = true;
      forgejo-netrc = {
        mode = "0600";
        # Git/libcurl also reads this path, so root can fetch the pinned
        # private Git input without embedding credentials in its URL.
        path = "/root/.netrc";
      };
      # Provision the registration credential, but do not start an unconfined
      # agent before its NixOS service and confinement have been migrated.
      orbit-environment.mode = "0600";
    };
  };

  users.users.root.hashedPasswordFile = config.sops.secrets.root-password-hash.path;
  users.users.okhsunrog.hashedPasswordFile = config.sops.secrets.okhsunrog-password-hash.path;

  nix.settings.netrc-file = config.sops.secrets.forgejo-netrc.path;
  systemd.services.nix-daemon = {
    requires = [ "sops-install-secrets.service" ];
    after = [ "sops-install-secrets.service" ];
  };
  systemd.tmpfiles.rules = [
    "d /var/lib/sops-nix 0700 root root -"
    "z /var/lib/sops-nix/key.txt 0000 root root -"
  ];
  environment.systemPackages = [
    pkgs.age
    pkgs.sops
  ];
}
