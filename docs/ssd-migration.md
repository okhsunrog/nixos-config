# SSD staging and NVMe migration

Use the existing root on the external HP S650 SSD directly. Keep
`nova_external/nixos0/root@ssd-backup-20261030T025128Z` unchanged as the source
for restoring the original system to NVMe; do not create another working root
clone. Prepare a reduced home separately, preserving application profiles,
authentication data, development configuration and `/home/.desktop-profiles`.

Before erasing NVMe, boot the SSD and verify that root, home and required
filesystems belong to the external pool, without depending on the NVMe pool.
Verify browser, Codex, ChatGPT, VPN and VKey access from that environment.

## Temporary SSD system

The `framework-ssd` configuration uses only `nova_external` filesystems and
the external ESP (`8494cd60-68e6-4ab9-991b-10f82988f3e0`). Its firmware entry
is `zbm-rs (SSD)`; the loader prefers pool GUID `3746946642497214640`.
USB storage drivers are included in both loader and OS initramfs.

Root and the separately received home are independent encryption roots. Both
use the existing runtime `/etc/zfs/zroot.key`; do not include that key in Git
or an ordinary Nix derivation. The disposable VM check exercises unlocking
both roots and mounting the temporary home after a fresh boot.

Build the SSD system explicitly:

```sh
nix build .#nixosConfigurations.framework-ssd.config.system.build.frameworkEfiPlan --out-link result-ssd-efi-plan
nix build .#nixosConfigurations.framework-ssd.config.system.build.toplevel --out-link result-framework-ssd
```

For offline signing, mount the SSD root and use
`sudo ./scripts/prepare-framework-loader.sh "$(readlink -e result-ssd-efi-plan)" --root /path/to/ssd-root`.
The helper checks the mounted root dataset and writes signing state and PCR
policy inside that root. Install the resulting system with `nixos-install
--root /path/to/ssd-root --system "$(readlink -e result-framework-ssd)"
--no-root-passwd --no-channel-copy`, with the SSD home mounted there too.
The ordinary `rebuild-framework.sh` still targets the NVMe configuration;
do not use it to update the temporary SSD system.

Arctern and both desktop backup policies are disabled on SSD, so the reduced
home cannot replace the full NAS backup. Nextcloud is not mounted and its
copied autostart entry is disabled. A current copy of
`/home/okhsunrog/Nextcloud/Passwords.kdbx` is placed at `~/Passwords.kdbx`
with mode `0600` in the temporary home. Keep the Nextcloud client closed
while using this environment.

The temporary home retains browser profiles, credentials, application state,
desktop profiles and the `zbm-rs`, `nixos-config`, `nixos-secrets`,
`floppa-vpn` and `rust/tangleaf` checkouts. Large build output, expendable
repositories, downloads, documents, Android development files and caches
are removed only from the staging clone. The full home remains on NVMe
and NAS.

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

## NVMe partitioning completed, 2026-10-30

The external pool scrub completed with zero errors. While booted entirely
from `nova_external`, the Samsung NVMe was discarded in full
(2,000,398,934,016 bytes) and repartitioned. The old NVMe pool and its data no
longer exist; restoration must use the SSD snapshots and full NAS home backup.

New layout:

| Partition | Size | Format | Identifier |
| --- | --- | --- | --- |
| 1 | 2 GiB | FAT32, `NVME_EFI` | PARTUUID `aafa93cb-dbf2-483c-8ca2-cb035104f8b9` |
| 2 | 48 GiB | LUKS2 containing swap | LUKS UUID `965b36af-dc40-4e5d-aa7b-49f49407c3ef` |
| 3 | Remaining space | ZFS `novafs` | PARTUUID `a06f78d5-95f1-4140-9c5c-1867ca180d23` |

The new pool GUID is `13099373940756918353`. It has one partition vdev,
`ashift=12`, `autotrim=on`, `autoexpand=off`, and **`compatibility=off`**;
no restriction to OpenZFS 2.3 was applied. NAS was observed running 2.3.2,
so validate future replication streams for its supported features separately.

Dataset defaults: `compression=zstd`, `recordsize=128K`, `atime=on`,
`relatime=on`, `xattr=sa`, `acltype=posix`, `dnodesize=auto`, `devices=off`,
`dedup=off`, `sync=standard`, `checksum=on`, `copies=1`, `overlay=off`.
The pool root uses AES-256-GCM with the existing passphrase file. Restored
raw datasets retain their original data keys and normalization properties;
explicitly verify the inherited operational properties after receiving them.

Swap was formatted with the existing `/etc/zfs/zroot.key` and tested
successfully. The NVMe configuration unlocks it in the initramfs after copying
the runtime secrets, then activates `/dev/mapper/nvme-swap` as ordinary swap.
The isolated SSD configuration does not unlock or activate this device.

Hibernation is not enabled: the current zbm-rs guard accepts only plain swap
partitions. LUKS2 support must cover the loader's pre-import image detection,
cancellation and target-initramfs resume gate together. Using stock resume
would bypass that protection. See `TODO.md`; suspend-to-RAM is unaffected.

There is a second blocker: the current signed kernel reports
`none [integrity] confidentiality` in `/sys/kernel/security/lockdown`.
Upstream Linux checks `LOCKDOWN_HIBERNATION` in `hibernation_available()`
(`kernel/power/hibernate.c`). Extending the LUKS2 guard alone does not resolve
that policy. Disabling Lockdown/Secure Boot or changing kernel image trust
requires a separate security decision; neither was weakened for migration.

## Dataset restoration completed, 2026-10-30

All four datasets were restored with full raw streams, independently of their
source ancestry. Each has `origin=-` and no pending receive token. Snapshot
GUIDs were compared and the existing key file was verified for every root.

| Target | Source snapshot | Snapshot GUID |
| --- | --- | --- |
| `novafs/nixos0/root` | SSD `root@ssd-backup-20261030T025128Z` | `13966331272922709518` |
| `novafs/nixos0/data/home` | NAS `home@arctern_2026-10-30T025936Z` | `7366286363519359454` |
| `novafs/nextcloud` | SSD `nextcloud@ssd-backup-20261030T014122Z` | `15626903444678666199` |
| `novafs/tmp_zfs_home` | SSD `tmp_zfs@ssd-backup-20261029T182707Z` | `8568705743908385826` |

These four raw datasets are independent encryption roots, in addition to the
encrypted pool root. All five use the same existing runtime key file. The
NVMe initramfs explicitly unlocks every root; matching passphrases do not
make independently received data keys inherit from the pool root.

During offline preparation the pool uses `cachefile=none` and altroot
`/home/okhsunrog/tmp_zfs/codex_tmp/nvme-repartition/target`. Restored mounts
must remain under that directory, without replacing the running SSD mounts.

## NVMe boot installation completed, 2026-10-30

Installed generation **69**, with the KDE parent and shared-home `niri`
specialisation. The native system is:

```
/nix/store/0j3w297nz9d9vziyr7hk4p59grx1h9sd-nixos-system-nova-nixos-26.11.20261020.02c087f
```

The signed loader is installed on the new internal ESP at
`EFI/zbm-rs/zbm-rs.EFI`, with an identical signed fallback at
`EFI/BOOT/BOOTX64.EFI`. Firmware entry `0001` (`zbm-rs`) points at the new ESP
and is first in the boot order. The external SSD entry `0004` is retained.
The old rescue/ZFSBootMenu entries still refer to the erased ESP; they were
not repurposed. Use the SSD for recovery if the first NVMe boot fails.

`novafs` bootfs is `novafs/nixos0/root`. Installation was performed offline
through a recursive bind mount at `/mnt/nvme-restore`, so Nix's local-store
permission checks do not require making the owner's private home traversable.
The running SSD system/profile were not switched.

Validation completed:

- Native KDE and niri closures built with the existing pinned kernel.
- The encrypted-pool VM booted with five independent encryption roots and
  automatically unlocked and activated LUKS2 swap using the same runtime key.
- The isolated SSD config still has no NVMe filesystems or swap dependency.
- Prepared root generation: Bootspec hash, kernel signature, CMS authorization
  and kernel/initramfs hashes verified with `scripts/verify-framework.sh`.
- Internal main/fallback EFI signatures checked; all pools reported healthy.

The VM check exposed an old root-written `__pycache__` in an installer store
output. That output was repaired through Nix. The installer now disables
bytecode before importing its support modules (zbm-rs commit `7a38a5e`),
with a regression test. The immutable diagnostic source used by this flake
retains the previous diagnostic changes and adds only that fix and its test;
unrelated dirty checkout changes were not bundled or reverted.

Physical firmware boot, TPM policy acceptance and desktop authentication
remain to be checked after the owner's manual reboot. Hibernation remains
disabled pending the encrypted-swap guard work described above.
