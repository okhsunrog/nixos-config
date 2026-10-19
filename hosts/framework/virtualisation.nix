{
  config,
  pkgs,
  lib,
  ...
}:
{
  virtualisation.docker.enable = true;
  # Floppa's tunnel MTU is 1280. Larger container MSS values stall downloads
  # through the tunnel, even though TCP connects and host networking works.
  virtualisation.docker.daemon.settings = {
    mtu = 1280;
    default-network-opts.bridge."com.docker.network.driver.mtu" = "1280";
  };
  virtualisation.libvirtd.enable = true;
  # The pool already protects this host key at rest. Libvirt's automatic
  # TPM policy picks the loader's PCR signing key, which does not authorize
  # this OS's current PCR 11 value after kexec.
  systemd.services.virt-secret-init-encryption.serviceConfig.ExecStart = lib.mkForce (
    pkgs.writeShellScript "libvirt-init-encryption" ''
      set -euo pipefail
      ${pkgs.coreutils}/bin/dd if=/dev/urandom status=none bs=32 count=1 |
        ${config.systemd.package}/bin/systemd-creds encrypt --with-key=host \
          --name=secrets-encryption-key - /var/lib/libvirt/secrets/secrets-encryption-key
    ''
  );
  programs.virt-manager.enable = true;
  users.users.okhsunrog.extraGroups = [
    "docker"
    "libvirtd"
  ];
}
