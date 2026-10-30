# Framework boot and recovery

## Current installation, checked October 30, 2026

The main signed zbm-rs image is installed at `EFI/zbm-rs/zbm-rs.EFI` on the
internal ESP, PARTUUID `aafa93cb-dbf2-483c-8ca2-cb035104f8b9`. Entry `0001` is
the current firmware boot entry. `EFI/BOOT/BOOTX64.EFI` contains the same main
image; it is not an independent recovery version. After the NVMe migration,
the new ESP has no rescue image or separate rescue firmware entry.

The prepared configuration now pins both the main source and the independently
retained rescue source to `dc82575eb2d0b9cd9e9db1dafc4172838db8b585`.
This published baseline has the cancellation-only rescue guard and still rejects
enforced resume. The rescue keeps its own Nixpkgs, kernel and ZFS. Normal
`rebuild-framework.sh` never installs or updates it. The explicit rescue updater
stages a candidate; promotion requires the exact tested hash and receipt, as
described below. The source pin is not by itself a pin of the complete artifact:
retain the built plan, public image inputs, manifest and closure too.

These are source-configuration changes, not an installed EFI update. Host
hibernation remains disabled. No rescue installation or firmware changes were
performed during this work.

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

The signed profile and rescue guard are implemented; authenticated repeat cycles
and the complete protected loader chain are still under validation. Do not
enable this policy for normal use until VM and physical acceptance have passed.
Keep Secure Boot and Lockdown enabled.

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

The experimental port subsequently passed full Linux 7.2.9 and matching ZFS
2.4.4 builds with a disposable VM trust certificate. The dedicated TPM/EFI/power
preflight compiled 124 objects with the required signature and integrity
Lockdown settings. The CRB EFI/kexec probe passed NV protection and PCR5
inheritance checks. Both CRB and TIS fixtures first exposed an inherited EFI
INITRD-table write corrupting the incoming
initramfs. The upstream-proposed ACPI-reclaim allocation fix is patch 0026;
its complete kernel/ZFS rebuild and CRB/SHA-256-only plus TIS/dual-bank handoff
checks passed. The RAM test then rejected a changed E820 map before image
authentication. A two-boot probe identified the moving range as the EFI boot
memory-map buffer, not the TPM/PCR5/INITRD table pool. Patch 0027 keeps that
x86-only buffer in ordinary memory passed/reserved through `boot_params`,
without disabling the E820 check. Its dedicated compilation preflight and full
kernel/ZFS rebuild passed. On October 31 the CRB/SHA-256 VM passed a real
authenticated RAM restore, retaining its boot ID, RAM-only data, healthy ZFS and
the target kexec prohibition. Its second hibernation failed because restored
RAM retained the previous TPM boot's NULL-primary context. Experimental patch
0028 adds an authenticated one-shot context handoff through reserved EFI memory;
the original provenance AK must sign a fresh nonce and the NULL-creation audit.
The signed image binds the old NULL identity and exact handoff address. Affected
objects compile; full build and repeat-cycle runtime acceptance are pending.
Backend v2 is a local extension, not an upstream-approved fix.

Separate negative-only runs rejected image-signature tampering and a cleared
guest TPM before pool import, then required cancellation on the next boot.
Unavailable-TPM, repeated cycles and the complete enforced loader integration
remain acceptance gates. This Framework currently uses CRB. The installed host
kernel/loader are unchanged; source pins have advanced to the guarded baseline
above, with hibernation still disabled.

Read-only hardware checks confirm that this Framework exposes only the SHA-256
PCR bank and records ExitBootServices invocation/success events in PCR5. These
are prerequisites, not authenticated-resume acceptance. VM coverage includes
CRB/SHA-256 and TIS/dual-bank configurations.

The boot-record v2 attempt protocol passed the ordinary encrypted-root RAM
restore VM, including the original boot ID, post-resume cleanup and agreement
between direct and cached swap-header reads. It keeps a kernel-consumed image
protected across failed verification and the following boot. Signature and reset
negative-only runs also passed with the authenticated kernel. A verified empty swap may cold-boot
for repair when TPM-backed hibernation is unavailable; a saved or incomplete
session must still be cancelled explicitly first.

The signed BootAuthorization v2 profile and trusted Nix build-contract validator
are implemented in the working zbm-rs tree. They bind the actual approved
kernel/initrd and normalized swap/credential policy, and are checked before
cloning and handoff, including cold boots. Real PE/IMA/CMS publisher validation
passed. This does not enable enforced resume yet: the authenticated RAM cycle
and complete protected-loader VM acceptance are still required.

After the complete hibernation path works and has passed acceptance, remove old
system generations and their stale prepared artifacts through the standard
pruning workflow. Retaining old kernels is not part of this deployment plan.
Intentional kexec through old kernels and research into their possible TPM
provenance bypass are outside scope. VM acceptance still covers the supported
patched-loader-to-patched-target path, authenticated RAM restoration and rejection
of corrupted images or invalid/unavailable TPM evidence.

## Independent rescue lifecycle

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
rescue as a side effect of normal main-loader updates. The candidate/known-good
publisher and its FAT/OVMF publication test are implemented in zbm-rs. Host pin
integration is prepared in this configuration, not installed. The exact unsigned production image booted in OVMF,
displayed the menu, accepted F2 and powered off directly with F10. No host disks
were attached, so that run does not certify production ZFS/LUKS access or physical
boot; the separate 19-scenario UI fixture covers virtual encrypted devices.

`./scripts/update-framework-rescue.sh` stages only
`EFI/zbm-rs/rescue-candidate.EFI` and appends its independent firmware entry.
The known-good `rescue.EFI` stays untouched. After testing that exact candidate,
`./scripts/update-framework-rescue.sh --promote TESTED_SHA256` verifies its
image, durable receipt, immutable plan and swap/credential policy before
publishing the known-good slot. A missing receipt or modified candidate is an
error. Main-loader rebuilds do not invoke this script.

The canonical `boot.loader.zbm-rs.hibernation.cancellationConfig` is derived from
the declared physical swap topology even while `hibernation.enable` is false.
Main resume activation retains that single enable switch; it also selects the
TPM-patched shared kernel, disables persistent loader diagnostics and enables
native NixOS resume-before-import. It remains false in this checkout pending
acceptance. Neither a rescue update nor a configuration build enables it.

Keep a tested bootable copy on a different physical device. Multiple files on
one ESP share filesystem and disk failure modes. Old rescue can also become
incompatible after pool feature upgrades; revalidate before enabling new
features. Firmware may try another entry if EFI launch fails, but a hang after
kernel handoff is not guaranteed to return control to firmware. Unsigned rescue
is therefore a manual firmware-menu path with Secure Boot deliberately disabled,
not an automatic downgrade from the protected loader.
