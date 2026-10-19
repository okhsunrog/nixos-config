# Arch to NixOS: home and VPN state

NixOS uses `novafs/nixos0/root` and `novafs/nixos0/data/home`. The latter is a
ZFS clone of `novafs/arch0/data/home@nixos-migration-20261019-044056`.
The 488 GiB home was not copied block by block: both datasets initially share
the snapshot's blocks, then independently allocate changed blocks. Both inherit
native encryption from `novafs`. Keep the origin snapshot while the clone uses it.

The old 14 MiB NixOS home was overlaid onto the clone to retain the existing
NixOS-specific setup, then renamed to
`novafs/nixos0/data/home-before-migration-20261019-044056`. It may be removed
after physical acceptance. The Arch home remains untouched.

`novafs/nextcloud` and `novafs/tmp_zfs_home` remain shared datasets mounted at
`~/Nextcloud` and `~/tmp_zfs`. They are not included in the home clone.

The clone preserves SSH/GPG keys, Codex authentication, user tools, KDE settings
and browser profiles. No Home Manager module is enabled. Nix-specific executable
paths in the cloned shell environment were corrected, as was the VKey launcher.
Browser process locks were removed only in the clone. Zen's existing
`Default (release)` profile is now the general default, matching the original
installation's active profile. Nix's Zen wrapper uses legacy shared-profile
selection, so a different store path does not select a new empty profile.
The installed browser is at least as new as the Arch profile's last version.
Websites can still require another login; copying a profile cannot guarantee
that a remote session remains accepted.

Floppa is built natively from a GitHub input pinned in `flake.lock`.
Its CLI, GUI, polkit helper and systemd units come from the upstream project's
NixOS module. API deployment metadata is checksum-pinned in the private Forgejo
registry; it contains no session or access token.

Five persistent files were copied byte-for-byte from a consistent root snapshot
to `/var/lib/floppa-vpn`: `settings.json`, `vpn-config.json`,
`server-session.json`, `runtime.json`, `endpoint-cache.json`. The target directory
is root-owned mode 0700, files mode 0600. Runtime intent was preserved, including
the Connect on boot preference. `rollback.json` and `network-rollback-v1` belong
to the old operating system's applied routes and must not be imported.
User-side Floppa state arrived with the home clone. Runtime secrets are not Git
configuration; protect/backup them through encrypted ZFS snapshots. Activation
does not overwrite mutable session and user preference files.

The generated boot generation must be published and signature-verified before
reboot. VM checks cover service/standalone operation and socket marking;
physical Wi-Fi, VPN endpoint access, TPM, browser login and restored desktop
session still require testing after booting NixOS. The Arch BE remains available.
