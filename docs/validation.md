# Validation status

## Framework NvPCR compatibility, 2026-10-19

Arch's last boot used systemd 262.1 and initialized the `hardware`,
`cryptsetup` and `login` NvPCRs successfully. It skipped the optional `verity`
NvPCR because the physical TPM's NV storage was full. NixOS's systemd 261.3
tried to reuse those indices with the older write authorization scheme and
failed with `File exists`. The old hwdb workaround is absent in Arch now.

Both systems already have identical public PCR keys, signed `initrd` policies
and NvPCR definitions. The fix uses systemd 262.1 in the NixOS initrd and
userspace, retaining the kernel, module signatures, NvPCR indices and keys.
The local package retains NixOS adaptations, rebasing its timezone/taint
patches and removing patches/options made obsolete upstream in 262.

An isolated swtpm test initialized four signed-policy NvPCRs and successfully
extended `hardware`. Running 261.3 on those same indices reproduced the
failure, while 262.1 could reuse them. No physical-host TPM was passed to QEMU.
The same VM then installed NixOS into an encrypted ZFS pool, booted the
original and updated generations via kexec, and booted a root snapshot clone.
The complete test passed in 77.62 seconds. A modified installer store artifact
initially failed NAR verification; it was rebuilt from its derivation and
verified before the successful rerun. Physical Framework NvPCR initialization
with the new package remains to be checked after reboot.
Logs and the adapted test fixture are under
`~/tmp_zfs/codex_tmp/nixos-tpm-arch-20261019/`.

## Native protected boot installation, 2026-10-17

The installed system is now native zbm-rs, pinned to source `95156ef`.
The previous ZFSBootMenu publisher and stable kernel/init aliases were removed.
ZFSBootMenu remains the default firmware entry and still boots Arch.

- Built and installed kernel 7.2.9 with explicit owner/IMA trust and forced
  module, kexec and integrity verification. The cached kernel was reused.
- Signed and independently verified all 7413 modules outside Nix. The public
  local input is a real directory, not a symlink escaping pure evaluation.
  Its manifest binds the modules to the exact kernel derivation.
- Installed native generation
  `/nix/store/akkx3a805irskqys80z7968zyg61xzzm-nixos-system-nova-nixos-26.05.20261003.825e202`.
  The original Bootspec/store artifacts are unchanged; prepared signed copies
  and authorizations live under `/boot/zbm-rs` on the root dataset.
- The real install hook appended runtime ZFS/PCR inputs, signed the kernel and
  final initrd and published the exact source-bound boot plan. Independent
  post-install checks verified EFI, IMA, CMS, hashes, hostid and early home.
- The appended public PCR policy matches Arch's four-entry policy byte for
  byte, retaining previous ZFSBootMenu and zbm-rs measurements. Actual initrd
  ZFS/Insyde module signatures were independently checked. Initrd unit-graph
  verification found no dependency cycles.
- Native TPM services retain the laptop's tested NvPCR allocation priorities
  and restore the Insyde EFI-variable view before early measured-OS checks.
  The pinned NixOS module's redundant systemd backport is filtered when using
  the matching 261.3 package; the rest of that package is unchanged.
- The encrypted native NixOS VM passed real installation, runtime-secret
  preparation, early home/user checks, missing-secret rollback, actual updated
  generation boot and source-snapshot clone boot (200.05 seconds).
- Separate signed OVMF/swtpm NixOS normal/snapshot tests passed. Altered
  arguments with the same signed kernel/initrd were rejected. Encrypted,
  enforced Arch normal/snapshot regression tests also passed.
- Workspace tests, strict Clippy, formatting, security-tool tests, ShellCheck
  and both host flake checks passed.
- Alternative signed EFI SHA256:
  `011f0e7131e81ab91b5ea805519f594fbe6100e208ea1fd0270c0be6104dbc2e`.
  It is at `/EFI/zbm-rs/zbm-rs.EFI`; the existing firmware entry still has the
  label `zbm-rs (Arch test)` but supports both systems. BootOrder is unchanged,
  with ZFSBootMenu first; neither of its EFI files changed and no BootNext was set.

Logs are retained in
`/home/okhsunrog/tmp_zfs/codex_tmp/nixos-secureboot-20261017/`.
Root-only signed releases, rollback boot files and policy staging are under
`/var/lib/zbm-rs/`. Runtime private keys never entered the source or Nix store.
Pre-change snapshots are named `before-zbm-rs-secureboot-20261017`.

Physical F12 boot into zbm-rs, both OSes, keyboard/recovery, hardware TPM/NvPCR,
niri/Rio and laptop hardware remain separate acceptance tests. No reboot was
performed during installation.

## Historical preparation, 2026-10-04

Preparation started on 2026-10-04 from the running Arch boot environment.

- NixOS configuration evaluates with the pinned `nixos-26.05` input.
- Selected kernel: 6.18.55; OpenZFS: 2.4.4; niri: 26.04.
- Niri configuration passes `niri validate` (`checks.x86_64-linux.niri-config`).
- ShellCheck and Nix formatting pass.
- The encrypted-disk VM passed installation, the first kexec boot, preservation
  of the current bundle when its key is missing, and booting an updated
  generation, booting the original snapshot clone, and publishing from that
  clone. The complete test passed in 104.22 seconds. VM discovery uses by-path because
  its disposable disk has no serial/by-id link.
- Full laptop-system build completed; its closure is approximately 6.5 GiB.
- The host pool is healthy and has approximately 859 GiB available after cleanup.
- Laptop installation completed in `novafs/nixos0/root` with its separate home.
  Kernel, private initramfs, hostid, dataset properties and copied secret files
  passed the post-install checks. Existing `bootfs` remains unset.
- The initial hierarchy quota was removed at the user's request; installation
  does not impose a dataset quota.
- Post-install checks were corrected to dereference the initramfs symlink and
  resolve `/etc/hostid` inside the target root.
- No physical NixOS boot, niri session or hardware validation has occurred.

## Home mount regression: red / green

- RED: adding a normal user to the encrypted-pool VM reproduced a first-boot
  failure. Account activation created `/home/probe` before mounting the home
  dataset; ZFS rejected the nonempty mountpoint with `overlay=off`, and the guest
  entered emergency mode. The test failed at its 300-second global timeout.
- Fix: `/home` has `neededForBoot = true` in both the laptop configuration and
  the VM fixture, so it mounts in initrd before account activation.
- GREEN: the complete VM test passed in 88.96 seconds, including the normal
  user's home ownership/dataset, absence of hidden root-dataset home directories,
  generation updates and snapshot-clone boot.
- Regression logs: `/tmp/nixos-home-red.log` and `/tmp/nixos-home-green.log`.
- The corrected laptop closure built successfully and was installed into the
  existing BE. Post-install checks passed, including the initrd mount declaration.
  Updated source is copied to `/etc/nixos`; the corrected state is snapshotted as
  `novafs/nixos0@home-mount-fix`. Earlier snapshots retain the old configuration.

Current build logs are `/tmp/nixos-framework-current.log` and
`/tmp/nixos-be-test-recovery.log`. Both builds finished successfully. The physical
installation log is `/tmp/nixos-framework-install.log`; the initial wrapper
stopped at its symlink-permission assertion, which was corrected and rerun.

## Personal Rio terminal

- Rio is pinned to `okhsunrog/rio` commit
  `11b8a338473898ff5d012f890eb0df06f66a8e2f`, matching the local Arch build,
  with Rust 1.96.1 and X11, Wayland, WGPU and audio enabled.
- The Rio package and complete laptop system built successfully. All 223
  frontend tests passed, including `base_layout_key_follows_pc101_position`
  and `alternate_keys_payload_fields` from the kitty keyboard patch.
- The packaged binary runs and reports `rioterm 0.5.28`; desktop integration,
  man page and the separate terminfo output are installed by the package.
- Niri configuration validation passed with Super+Enter launching Rio.
  Foot remains installed as a fallback.
- The complete system was installed into `novafs/nixos0/root`. Post-install
  boot/secret/home checks passed; Rio and foot version commands and niri
  validation passed inside the installed root. The pre-update snapshot is
  `novafs/nixos0@before-rio`, and the installed state is `@rio-installed`.
  Dataset quota remains `none`, and pool `bootfs` remains unset.
- Installation log: `/tmp/nixos-rio-install.log`.
- Build log: `/tmp/nixos-rio-final-build.log`. No graphical Rio session on the
  physical NixOS system has been tested yet.
