# Framework boot and recovery

## Current installation, checked October 30, 2026

The main signed zbm-rs image is installed at `EFI/zbm-rs/zbm-rs.EFI` on the
internal ESP, PARTUUID `aafa93cb-dbf2-483c-8ca2-cb035104f8b9`. Entry `0001` is
the current firmware boot entry. `EFI/BOOT/BOOTX64.EFI` contains the same main
image; it is not an independent recovery version. After the NVMe migration,
the new ESP has no rescue image or separate rescue firmware entry.

`hosts/framework/efi.nix` already builds a separate unsigned rescue. Its source
is pinned to `4038ff09a44c674fc1b4b1126b0f21aa4d09706a`, with its own Nixpkgs,
kernel and ZFS. Normal `rebuild-framework.sh` never installs or updates it.
`framework-rescue-update` explicitly builds `frameworkRescuePlan` and invokes
the EFI installer for `EFI/zbm-rs/rescue.EFI`. The installer rejects a signed
rescue, preserves other EFI files and appends a missing firmware entry without
moving existing entries. It replaces one rescue file; there is no VM gate or
retained rescue slot in this command today. Its installer and some image inputs
still come from the current configuration, so the source pin alone is not a pin
of the complete resulting artifact.

The old rescue predates native hibernation guards. It is not the future
cancellation-only rescue and must not be assumed safe around a pending image.
Host hibernation remains disabled. No rescue installation or firmware changes
were performed as part of this architecture review.

## Agreed protected hibernation direction

The authoritative generic design lives in zbm-rs
`docs/hibernation-design.md`; this file records deployment consequences.

- Main loader: signed, enforced target authorization, outgoing verified
  `kexec_file_load`, and the TPM NV/provenance protection required by the selected
  Garrett backport.
- Target NixOS: integrity Lockdown, authenticated RAM images in LUKS2 swap, early
  resume before any ZFS import. Share the protected `kernelPackages` with the
  main loader, keeping kexec compiled in. Separate loader/target kernel builds
  and compile-time exclusion of target kexec are not requirements. Set
  `sysctl.kernel.kexec_load_disabled=1` in target boot arguments; Linux applies
  this before initramfs `/init`, disabling further kexec loads in NixOS.
- Rescue: separate unsigned EFI boot, no hibernation/resume, no protected TPM
  capability advertisement, but the same swap detection and verified cancellation
  before booting an OS, exposing an unrestricted shell or mutating pools.
- Protected boot targets need a new signed, validated capability profile for
  exact kernel/initramfs/arguments/root. Ordinary signatures and old authorization
  records are insufficient. The restriction also applies to cold boots through
  the capable main loader.
- Normal resume remains the default. Explicit image discard can either stay in
  the menu or cold-boot the exact selected target. Destructive continuations
  require confirmation; poweroff preserves the image without a prompt.

The kernel port, provenance tests, signed profile and rescue guard
are incomplete. Do not enable this policy in the host configuration until those
gates and physical testing have passed. Keep Secure Boot and Lockdown enabled.

Full root currently has access to boot/IMA signing keys in `/var/lib/secureboot`.
The shared-kernel baseline accepts that such a compromise is already beyond the
trusted-boot boundary. No concrete configured path with kexec authority but no
signing-key access was identified in this review. The main loader's signed
profile itself cannot constrain later kexec calls from NixOS. The early sysctl
policy is now configured in `hosts/framework/secureboot.nix` without a separate
kernel build or initramfs service. It takes effect in a newly booted generation
after rebuilding/installing; editing the configuration does not change the
running kernel. Loader and rescue command lines are constructed independently
and retain outgoing kexec. The exact target argument is covered by ordinary
BootAuthorization signing. Compile-time exclusion remains outside this plan.

Validation on October 30: the disposable encrypted ZFS/LUKS hibernation VM in
zbm-rs passed with the target prohibition already set before udev and resume.
Both kexec load interfaces and resetting the sysctl were rejected before and
after actual RAM restoration; bootstrap retained kexec. The test used ordinary
Linux 6.18.55, not the unfinished TPM/Lockdown backport. The host configuration
evaluates with the argument for KDE and niri and retains its existing 7.2.9 kernel
derivation. No host rebuild, reboot or runtime sysctl change was performed here.

After the complete hibernation path works and has passed acceptance, remove old
system generations and their stale prepared artifacts through the standard
pruning workflow. Retaining old kernels is not part of this deployment plan.
Intentional kexec through old kernels and research into their possible TPM
provenance bypass are outside scope. VM acceptance still covers the supported
patched-loader-to-patched-target path, authenticated RAM restoration and rejection
of corrupted images or invalid/unavailable TPM evidence.

## Planned rescue lifecycle

Retain a deliberately chosen known-good rescue, rather than automatically using
the preceding development commit. Pin all its image inputs and retain the exact
EFI artifact, manifest/hash and build closure independently of system-generation
GC. Its age is less important than demonstrated bootability and compatibility
with the current pool and target boot formats.

Build a new rescue as a candidate. Test the exact final EFI bytes in OVMF,
including menu/input, disposable encrypted ZFS/LUKS unlock, cancellation and shell
recovery. A separate SSH-enabled test image does not certify production bytes.
Install the candidate at a separate path/entry while preserving the known-good
one. Promote it only after an explicit successful physical boot. Do not refresh
rescue as a side effect of normal main-loader updates. These validation/promotion
steps and multiple rescue slots still need implementation.

Keep a tested bootable copy on a different physical device. Multiple files on
one ESP share filesystem and disk failure modes. Old rescue can also become
incompatible after pool feature upgrades; revalidate before enabling new
features. Firmware may try another entry if EFI launch fails, but a hang after
kernel handoff is not guaranteed to return control to firmware. Unsigned rescue
is therefore a manual firmware-menu path with Secure Boot deliberately disabled,
not an automatic downgrade from the protected loader.
