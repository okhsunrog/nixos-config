# SSD staging and NVMe migration

Use the existing root on the external HP S650 SSD directly. Keep
`nova_external/nixos0/root@ssd-backup-20261030T025128Z` unchanged as the source
for restoring the original system to NVMe; do not create another working root
clone. Prepare a reduced home separately, preserving application profiles,
authentication data, development configuration and `/home/.desktop-profiles`.

Before erasing NVMe, boot the SSD and verify that root, home and required
filesystems belong to the external pool, without depending on the NVMe pool.
Verify browser, Codex, ChatGPT, VPN and VKey access from that environment.

## Full home restoration from NAS

NAS: `10.77.77.100`, dataset
`okdata/backups/nova/novafs/nixos0/data/home`.

Latest backup verified on 2026-10-30: `arctern_2026-10-30T025936Z`
(05:59 Moscow time), GUID `7366286363519359454`, matching the local snapshot.
Refresh and verify the final backup before erasing NVMe; do not assume this
snapshot will still be the final restoration point.

The NAS home is a clone of its archived Arch home. Restore **only the selected
home snapshot as a full raw stream**, using `zfs send -w -p DATASET@SNAPSHOT`.
Do not use `-R`, `-i`, `-I` or a receive-side `origin` override for this initial
restoration. Receive into a new dataset with `zfs receive -u -s`, explicitly
setting the intended writable home mount properties rather than inheriting
the NAS backup's disabled mount settings. Do not restore the Arch hierarchy.

After receiving, verify the snapshot GUID and `zfs get origin`: the restored
home must have `origin=-`. Its encryption key must be available independently
of the NAS Arch dataset before attempting normal boot.

## NVMe repartitioning

Target: Samsung SSD 970 EVO Plus 2TB, serial `S59CNM0W814286M`.
Planned layout: ESP, 48 GiB swap partition, remaining capacity for ZFS.

After the SSD boot and backup verification, and after stopping all use of the
old NVMe pool, consider a single whole-device `blkdiscard` **before** creating
the new partition table. This is destructive, not an operation to run on the
current mounted system. Verify the disk by its stable identity at that step.
The device supports discard; the current pool already has `autotrim=on`.
Discard tells the controller that the old blocks are free; it does not reset
flash wear or require a secure erase/sanitize operation.
