# Framework boot and recovery

## Current installation, checked October 31, 2026

The main signed zbm-rs image is installed at `EFI/zbm-rs/zbm-rs.EFI` on the
internal ESP, PARTUUID `aafa93cb-dbf2-483c-8ca2-cb035104f8b9`. Entry `0001` is
the current firmware boot entry. `EFI/BOOT/BOOTX64.EFI` contains the same main
image; it is not an independent recovery version. The independent unsigned
rescue candidate is now staged at `EFI/zbm-rs/rescue-candidate.EFI`, entry `0002`.
Its SHA-256 is
`752790bff27fce1412b63441d3f35b335fc9f372dddc8ae55de3621691345a8f`.
The existing boot order still starts with `0001`; no BootNext was set. The
candidate has not been physically accepted or promoted to `rescue.EFI`.

The prepared configuration pins the main source to
`911e6b06457cc1ba6a6df84260cf9cb361d72eaf`, with the VM-tested experimental
authenticated-resume backend. The independently retained rescue stays at
`dc82575eb2d0b9cd9e9db1dafc4172838db8b585`, the cancellation-only guarded
baseline which rejects enforced resume. The rescue keeps its own Nixpkgs, kernel and ZFS. Normal
`rebuild-framework.sh` never installs or updates it. The explicit rescue updater
stages a candidate; promotion requires the exact tested hash and receipt, as
described below. The source pin is not by itself a pin of the complete artifact:
retain the built plan, public image inputs, manifest and closure too.

The configuration enables protected hibernation on the internal NVMe installation;
the portable SSD retains ordinary paging without hibernation. The owner-signed
production build is in progress. The running kernel and main EFI image have not
yet been replaced. The rescue candidate is installed separately as described above.

Source validation on October 31 passed after the main input update: Nix formatting,
ShellCheck, `ssd-config` and the disposable encrypted ZFS/LUKS storage-boot VM.
Lockfile comparison confirmed that only the main zbm-rs node changed. KDE and
niri retain the early kexec prohibition; the rescue policy remains `cancel-only`.
Evaluation with the hibernation option enabled selects backend
`linux-tpm-signature-v2`, context-handoff protocol 1 and record protocol 2 with
the configured LUKS2/ZFS-unlock topology. These checks do not establish physical
hardware acceptance.

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

The signed profile and rescue guard are implemented. Authenticated RAM restore,
subsequent hibernation and the complete protected loader chain passed disposable
VM testing with the experimental backend. Physical acceptance remains pending;
do not enable this policy for normal use until it passes too.
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
The signed image binds the old NULL identity and exact handoff address. Its full
kernel/ZFS build passed; CRB/SHA-256 and TIS/dual-bank VMs restored original RAM
and created the next signed image successfully.
Backend v2 is a local extension, not an upstream-approved fix.

After successful restoration and the next hibernation, separate runs rejected
image-signature tampering, a changed RAM-payload byte with its original signature
trailer intact, and a cleared guest TPM before pool import. Consumed images still
required cancellation on the following boot. The complete OVMF Secure Boot →
enforced zbm-rs → PE/IMA/CMS-authorized NixOS chain restored RAM and created the
next image. It also checked missing/wrong signed profiles, F10 preserving swap,
confirmed discard-only staying in the menu and cold boot after cancellation.
This Framework currently uses CRB. The running host kernel/loader still predate
this deployment; physical hibernation has not been attempted.

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

The patch-0028 CRB/SHA-256 interruption test restored one RAM session three
times. A deliberately unavailable guest TPM stopped resume before pool import
and left the image intact; restoring the exact clean initramfs/TPM allowed retry,
the next hibernation and the third restoration. The original boot ID, RAM-only
data, healthy pool and early kexec prohibition survived; the finish hook cleared
the durable attempt record. The same three-restoration interruption scenario also
passed with Linux's default image compression enabled. A separate complete
protected-chain VM passed with a compressed image too. Both runs retained the
separate disposable VM signing identities; owner keys were not passed to guests.

Empty-swap repair without TPM also passed with integrity Lockdown and ordinary
paging. This explicit repair scenario uses `systemd.tpm2_wait=0` so systemd does
not wait for a firmware-advertised device that the fixture deliberately unbound.
It does not waive TPM/image verification when a saved session exists.

The signed BootAuthorization v2 profile and trusted Nix build-contract validator
are implemented and passed the complete protected-chain VM test. They bind the actual approved
kernel/initrd and normalized swap/credential policy, and are checked before
cloning and handoff, including cold boots. Real PE/IMA/CMS publisher validation
passed. Backend `linux-tpm-signature-v2` requires context-handoff protocol 1 and
boot-record protocol 2. This host still needs a matching owner-signed kernel,
target and loader build using its public trust certificates and physical
acceptance. The disposable VM's signed artifacts are not reused.

After the complete hibernation path works and has passed acceptance, remove old
system generations and their stale prepared artifacts through the standard
pruning workflow. Retaining old kernels is not part of this deployment plan.
Intentional kexec through old kernels and research into their possible TPM
provenance bypass are outside scope. VM acceptance still covers the supported
patched-loader-to-patched-target path, authenticated RAM restoration and rejection
of corrupted images or invalid/unavailable TPM evidence.

## Physical acceptance after installation

Installation uses `./scripts/rebuild-framework.sh boot`: it prepares the next
boot without switching the running desktop or rebooting automatically. Keep the
previous generations until the new boot and repeated hibernation pass.

First test the staged rescue through the firmware menu with Secure Boot disabled.
Only promote the exact candidate hash after a successful physical boot. Re-enable
Secure Boot before returning to the protected main entry.

After booting the new internal generation, check the active closure, the
`[integrity]` Lockdown mode, the target kexec prohibition, available sleep states,
and early resume/TPM logs:

```sh
readlink -f /run/current-system
cat /sys/kernel/security/lockdown
sysctl kernel.kexec_load_disabled
cat /sys/power/state
journalctl -b -u zbm-resume.service
sudo journalctl -b -k | rg -i 'tpm|hibern|lockdown|signature|zfs'
```

Then test successive hibernation/restoration cycles from the same desktop session,
checking its unchanged `/proc/sys/kernel/random/boot_id` and application state.
Verify the restored kernel reports `Restored authenticated NULL-primary context`,
the next hibernation succeeds, and the pool stays healthy. These are physical
acceptance steps, not results established by the disposable VM tests. Do not
clear or reprovision the physical TPM as part of this check.

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
integration has staged the candidate, without promotion. The exact unsigned production image booted in OVMF,
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
native NixOS resume-before-import. It is enabled for the internal installation and
disabled for the portable SSD. A rescue update does not change that switch.

Keep a tested bootable copy on a different physical device. Multiple files on
one ESP share filesystem and disk failure modes. Old rescue can also become
incompatible after pool feature upgrades; revalidate before enabling new
features. Firmware may try another entry if EFI launch fails, but a hang after
kernel handoff is not guaranteed to return control to firmware. Unsigned rescue
is therefore a manual firmware-menu path with Secure Boot deliberately disabled,
not an automatic downgrade from the protected loader.
