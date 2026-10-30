{ config, lib, ... }:
{
  framework.storage = {
    pool = "nova_external";
    espPartuuid = "8494cd60-68e6-4ab9-991b-10f82988f3e0";
    portable = true;
    efiLabel = "zbm-rs (SSD)";
    preferredPoolGuid = "3746946642497214640";
    nextcloud = false;
    swapLuksUuid = null;
    tmpDataset = "${config.framework.storage.homeDataset}/tmp_zfs";
    encryptionRoots = [
      config.framework.storage.rootDataset
      config.framework.storage.homeDataset
    ];
  };
  # The reduced temporary home must never replace the full NAS backup.
  services.arctern.enable = lib.mkForce false;
  systemd.services.arctern.enable = false;
  framework.environments.entries.kde.backup = lib.mkForce "none";
  framework.environments.entries.niri.backup = lib.mkForce "none";
  # Nextcloud is intentionally absent from the temporary SSD environment.
  # Suppress the copied autostart entry so an empty local directory cannot
  # be interpreted as deletions to propagate to the server.
  home-manager.users.okhsunrog = { lib, pkgs, ... }: {
    home.activation.ssdNextcloudAutostart = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${pkgs.coreutils}/bin/install -D -m 0644 ${pkgs.writeText "nextcloud-ssd-autostart.desktop" ''
        [Desktop Entry]
        Type=Application
        Name=Nextcloud
        Hidden=true
      ''} "$HOME/.config/autostart/Nextcloud.desktop"
    '';
  };
}
