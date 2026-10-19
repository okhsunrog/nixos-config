# Arctern: Arch to NixOS

The active sender is now NixOS. The native package and service come from the
pinned Arctern input. `hosts/framework/arctern.toml` is the non-secret runtime
configuration; SOPS decrypts the existing replication identity from the private
`host-secrets` input. Mutable history and the administrator token remain in
`/var/lib/arctern`, copied from Arch with their original permissions.

Local snapshots cover `novafs/nixos0/root` and `novafs/nixos0/data/home` every
15 minutes, using the previous retention grid. Only home is sent to Mira.
Nextcloud stays excluded because its server has its own backup history;
temporary build datasets are not part of home. Automatic replication uses the
LAN route at most once a day. The WireGuard route still requires Send now.

Arch's Arctern unit is disabled in the mounted Arch root. Its datasets and NAS
backup history remain intact. Do not run the two sender configurations against
the same receive dataset after their histories diverge.

## One-time incremental bootstrap

NixOS home was cloned from
`novafs/arch0/data/home@nixos-migration-20261019-044056`. The clone did not acquire
the parent's snapshot names. Arctern's normal planner examines snapshots and
bookmarks belonging to its configured sender, not ancestor datasets.

Mira's newest received Arch home snapshot was
`arctern_2026-10-18T150335Z`, GUID `5951443111416458379`. Its corresponding local
cursor bookmark survived pruning. Copying that bookmark into the NixOS clone
as `#migration-from-arch-20261019` provides a valid incremental base.

The initial raw incremental sends that base to
`novafs/nixos0/data/home@arctern_2026-10-19T084517Z`. The receiver is a **new**
dataset, `okdata/backups/nova/novafs/nixos0/data/home`, created by
`zfs receive -u -s -o origin=<Arch-backup>@<base>`, with `mountpoint=none` and
`canmount=off`. Supplying `origin` to receive is important: pre-creating an
empty clone does not provide a received snapshot for an ordinary incremental
receive. This raw-send/receive procedure was tested on disposable encrypted
datasets before applying it to home.

ZFS estimated the delta at 17,530,291,032 bytes, versus approximately 491 GiB
of referenced home data. It neither rolls back nor replaces the Arch backup.
The new NAS dataset shares its old blocks through its clone origin.

The daemon initially used `dry_run = true` while the external bootstrap was
active, avoiding two concurrent receivers. The external stream was then
interrupted resumably and handed to Arctern. Its dry-run planner confirmed
`resuming from token` at byte 649,677,012 using the clone's copied bookmark.
Normal replication is enabled after the external receiver has exited.
The temporary `arctern_nixos_bootstrap` hold was released only after Arctern
placed its own `arctern_step_J_push_to_mira_P_mira` hold on the source snapshot.
Arctern now owns snapshot protection, retries and cursor-bookmark maintenance.
Future sends use Arctern's existing GUID planner and cursor bookmarks without
a special migration implementation.

If interrupted, preserve the held source snapshot and the receiver's
`receive_resume_token`. Resume with `zfs send -t <token>` into the same receive
dataset using `zfs receive -u -s`; do not restart with a full send or destroy
the old backup. Diagnostics for this cutover live under
`~/tmp_zfs/codex_tmp/arctern-nixos-migration-20261019/`; they are not required
by the installed service.
