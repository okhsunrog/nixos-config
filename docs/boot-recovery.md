# Framework boot and recovery

## Current installation, checked October 31, 2026

The internal ESP is PARTUUID `aafa93cb-dbf2-483c-8ca2-cb035104f8b9`.
Three independently published EFI files are installed:

| Firmware entry | Role | EFI path | Source |
| --- | --- | --- | --- |
| `0001`, `zbm-rs` | signed main loader, enforce | `EFI/zbm-rs/zbm-rs.EFI` | `638ad4cd1f3d575e2caceb11848542fb7cdea98c` |
| `0000`, `zbm-rs (rescue)` | physically accepted, unsigned known-good | `EFI/zbm-rs/rescue.EFI` | `9e51e993c58899a185c3b587ff9ba707604c67e7` |
| `0002`, `zbm-rs (rescue candidate)` | tested candidate, now also promoted to known-good | `EFI/zbm-rs/rescue-candidate.EFI` | `9e51e993c58899a185c3b587ff9ba707604c67e7` |

SHA-256 readback from all three ESP files passed. The main PE signature was
verified against the owner certificate; both rescue images were verified unsigned:

- Main: `7449b0c6ef0df34f0eda39108fe5cdaaa8e39f2ffd0f20a471b440edcadb4a54`.
- Known-good rescue: `c681020f3cfb5ee474ef11ff0b1087a7f2ec7df8a285ff058c3e7d4e0ba9df1b`.
- Candidate: `c681020f3cfb5ee474ef11ff0b1087a7f2ec7df8a285ff058c3e7d4e0ba9df1b`.

The owner physically verified rejection of the old candidate with Secure Boot
on, its startup with Secure Boot off, and subsequently booted Niri through it
(`BootCurrent=0002`). With explicit owner approval, that exact candidate was
promoted to known-good before updating the candidate slot. The updated candidate
passed exact-production-byte OVMF menu, F2 and direct F10 poweroff checks. No host
disks were attached. The owner subsequently confirmed that the updated candidate
was fully functional and booted Niri by default. Following the agreed lifecycle,
that exact `c681020f…` artifact was promoted with hash/receipt verification.
Known-good and candidate currently contain identical tested EFI bytes; future
candidate staging still leaves known-good untouched. Both rescue slots remain
cancellation-only. Physical hibernation acceptance through the main loader remains
separate from this rescue acceptance.

BootOrder is `0001,2001,2002,2003,0002,0000`; the protected main stays first.
No BootNext was set. The obsolete signed migration fallback at
`EFI/BOOT/BOOTX64.EFI` was removed earlier at the owner's request; its hash was
`3996cbd48195b36974e275eae325be7cf0adb0f3331446eb0a15838243407b30`.
It was the old `zbm-rs diagnostic` image, not the unsigned rescue. Normal
installation does not recreate that fallback.

Generation **72** provided the physical acceptance baseline:

- KDE parent: `/nix/store/81m820l539g23972mn0dy7r4hh2ivsr0-nixos-system-nova-nixos-26.11.20261020.02c087f`.
- Niri: `/nix/store/dw75lz0hirlh7dm33wbhbvlig7lnafi1-nixos-system-nova-nixos-niri-26.11.20261020.02c087f`.

Main and candidate now prefer the Niri specialisation for ordinary boot. The
main loader still prioritises the exact saved-session target. Key-unlock progress
and broker-reported pool refresh scope are enabled. The kernel was reused and
all 7410 existing aggregate module signatures were revalidated. Installation did
not switch or reboot the running session. Generation 72 subsequently booted
through the main loader with Secure Boot and integrity Lockdown. Its first
physical hibernate/resume succeeded on October 31, 19:41–19:43 Moscow time:
`boot_id` remained `50696601-278d-44c4-bfd9-629d9772e9d2`, the kernel logged
`Restored authenticated NULL-primary context`, the hibernate unit finished
successfully, and the image status returned to `inactive`. ZFS reported all pools
healthy and no system services were failed. Follow-up driver warnings were
`spd5118_resume` error -6 and USB evaluate-context warnings for ports 3-9/3-10;
the affected DIMM temperature sensor remained readable. A second consecutive
cycle through the Dux power menu succeeded at 19:52–19:54, with the same boot ID,
another authenticated NULL-primary context restore, a successful hibernate unit,
inactive image status and healthy pools. Explicit cancellation and physical
suspend-then-hibernate acceptance remain pending.

The subsequent standard `rebuild-framework.sh boot` installed generation **73**
with zbm-rs `638ad4c` and the guarded suspend-then-hibernate integration:

- KDE parent: `/nix/store/cr06vj2ncj2addr0b31h8q3vy8vwsafy-nixos-system-nova-nixos-26.11.20261020.02c087f`.
- Niri: `/nix/store/k6c8fil61np0jr6kdqr9c2jwni845ypk-nixos-system-nova-nixos-niri-26.11.20261020.02c087f`.

The Niri closure was activated with `switch-to-configuration test` without a
reboot. Logind reports both `CanHibernate=yes` and
`CanSuspendThenHibernate=yes`; the active timeout is `2h` and hybrid sleep is
disabled. The native composite unit has fail-closed preparation/completion hooks.
The cached kernel and all 7410 existing signed module payloads were retained;
only module provenance metadata was refreshed. Secure Boot remains enabled,
integrity Lockdown and the early kexec prohibition remain active, the image is
inactive, pools are healthy and no system services are failed. Main EFI signature
and readback passed; both rescue hashes and firmware order are unchanged. The new
main EFI has not yet received a physical firmware boot, and automatic RTC wake
still needs the short physical test below.

Validation passed: 98 Rust tests, formatting and Clippy; configuration checks;
16 loader smoke scenarios; direct encrypted RAM restore; composite preparation
refusal, pending-image activation refusal without header changes, early wake,
failed-hibernation fallback and two repeated timed restorations. The compressed
TPM CRB/SHA-256 variant with runtime systemd 262.1 also passed TPM absence/retry
and a subsequent direct cycle, for four authenticated restores. The composite
VMs inject ACPI power-button wakes and do not establish RTC alarm delivery.

The internal installation enables backend `linux-tpm-signature-v2`, authenticated
context-handoff protocol 1 and record protocol 2 with the declared LUKS2/ZFS
credential topology. KDE and Niri retain the early kexec prohibition. The portable
SSD retains ordinary paging without hibernation. Rust tests, Clippy, configuration
checks, ordinary cross-pool unlock smoke, preferred-specialisation kexec, the
19-scenario resume/cancellation fixture and the encrypted ZFS/LUKS storage-boot
VM passed before installation. Nix formatting and ESP readback passed after the
rescue update. VM results do not establish physical hibernation acceptance.

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
VM testing with the experimental backend. Two consecutive physical authenticated
resumes passed, through the CLI and Dux. Cancellation and suspend-then-hibernate
acceptance remain pending before treating the whole workflow as accepted.
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
boot-record protocol 2. This host now has matching owner-signed kernel, target
and loader artifacts installed and two successful physical authenticated resumes.
Cancellation and suspend-then-hibernate still need physical acceptance. The disposable
VM's signed artifacts are not reused.

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

Suspend-then-hibernate uses the same preparation/completion gate on its own
native systemd service. The internal configuration selects a two-hour timeout;
closing the lid requests suspend-then-hibernate unless logind considers the
machine docked (including multiple connected displays), when the lid is ignored.
The portable repair system retains ordinary suspend. UPower uses percentage
thresholds of 20% low, 10% critical and 5% action; the internal installation
explicitly selects Hibernate as its critical action.

Request the new mode with `systemctl suspend-then-hibernate`. Dux's “Suspend
behavior” setting applies only to idle sleep, separately for AC and battery.
To use the mode from its Suspend menu button, set that button's custom command
to `systemctl suspend-then-hibernate`. Enable “Lock before suspend” to lock
before sleep, including hibernation and requests arriving through logind.
These Dux preferences are user settings, not declarations in this configuration.
Plain `systemctl suspend` remains ordinary suspend. In suspend-then-hibernate,
systemd also handles low-battery wake/hibernation independently of UPower;
its firmware-dependent wake path still needs physical acceptance.

For the first physical timed-wake test, shorten only the runtime timeout:

```sh
sudo install -d /run/systemd/sleep.conf.d
printf '[Sleep]\nHibernateDelaySec=2min\n' | sudo tee /run/systemd/sleep.conf.d/99-framework-s2h-test.conf >/dev/null
systemctl suspend-then-hibernate
```

After restoring the session, remove the override to restore the two-hour policy:

```sh
sudo rm /run/systemd/sleep.conf.d/99-framework-s2h-test.conf
journalctl -b -u systemd-suspend-then-hibernate.service
```

First also check a manual wake before the timeout, then repeat a complete timed
cycle. The VM harness injects ACPI wake events because its RTC path was unreliable;
it verifies timer decisions and actual RAM restoration, not the Framework's RTC
or low-battery wake capability. Do not infer those physical results from VM tests.

### Early RTC wakeup and the local systemd patch

On 2026-11-01 the Framework reproduced upstream systemd issue
[#38193](https://github.com/systemd/systemd/issues/38193) with systemd 262.1.
Tracing with the `boot` clock captured two unsuccessful timed transitions:
systemd polled its timerfd about 28 ms and 125 ms before its actual deadline,
received no event, and treated the wakeup as manual. A third cycle crossed the
deadline and successfully hibernated and resumed. The repeated sleep requests
with the lid still closed were separate logind operations.

`packages/systemd-s2h-timer.patch` shares a timer-readiness helper between the
ACPI battery-alarm and software battery-estimation paths. If the timerfd has
between zero and one second remaining, it waits up to one second for the real
event. Distant deadlines, disarmed timers, and already expired timers retain a
nonblocking poll. Readiness is not consumed and hibernation is not requested
before the timer actually expires. This is a bounded RTC-granularity workaround;
it does not establish whether a near-deadline wake was caused by RTC or input.
A user waking the machine within the final second may therefore still get
hibernation. Skew greater than one second is outside its scope.

The package build runs `test-sleep-timer` against real timerfds, covering the
28/125 ms observations, a 750 ms early wake, a distant manual wake, expired and
disarmed timers, and an invalid descriptor. Physical acceptance of the patch
uses repeated two-minute timed cycles and a manual wake well before the
deadline, with the same kernel/RTC/timerfd tracing used for the original failure.
Keep the normal two-hour policy and the ZBM preparation/completion guards.

Three additional physical cycles passed on November 1, using the patched
`systemd-sleep`: suspend at 05:15:39, 05:23:51 and 05:31:57 Moscow time led to
automatic hibernation at 05:17:40, 05:25:52 and 05:33:58. All three authenticated
RAM restores succeeded, the TPM NULL-primary context was restored, and ZFS pools
remained healthy. The retained traces have no overruns. Timer polling occurred
1.103 s, 0.977 s and 1.217 s after the respective deadline, so these runs validate
repeated automatic transitions but did not exercise the new early-wake wait
branch on hardware. Generation 79 subsequently installed the patched systemd
through the normal host package configuration, and its Niri specialisation was
activated live. PID 1 and the native suspend-then-hibernate service now use the
patched package; the service uses the same binary that passed these physical
cycles. The ordinary two-hour timeout is active. The temporary service override,
private tracing instance and extra sleep debug logging were removed; retained
diagnostic artifacts are no longer used by the service.

The patched host package also passed the disposable encrypted-pool VM on
2026-11-01: manual wake before the timeout, preparation refusal, preservation of
a pending swap header, failed-hibernation fallback, and four authenticated
compressed-image restorations with CRB/SHA-256 TPM, including TPM-unavailable
refusal/retry and a subsequent direct hibernation. This VM uses the existing
post-deadline ACPI wake injection; the early-wake window is covered by real
timerfd unit tests. The physical results above establish automatic timed
transitions on the Framework; the early-wake wait branch still has unit-test
coverage rather than an observed physical invocation.

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
integration retains the physically accepted image in the known-good slot and
stages new builds separately in the candidate slot. The updated exact unsigned
production image booted in OVMF, displayed the menu, accepted F2 and powered off
directly with F10. No host disks
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
Main resume activation retains that single enable switch; it disables persistent
loader diagnostics and enables
native NixOS resume-before-import. It is enabled for the internal installation and
disabled for the portable SSD. A rescue update does not change that switch.
The Framework internal and portable profiles always share the same TPM-patched
kernel and aggregate signed module input; disabling resume does not select an
incompatible second kernel. Configuration checks cover that identity explicitly.
The portable profile still disables hibernation. The separate rescue keeps its
own independently pinned kernel/package set. The disposable encrypted-storage
boot VM passed again after this correction (78.15 seconds).

Keep a tested bootable copy on a different physical device. Multiple files on
one ESP share filesystem and disk failure modes. Old rescue can also become
incompatible after pool feature upgrades; revalidate before enabling new
features. Firmware may try another entry if EFI launch fails, but a hang after
kernel handoff is not guaranteed to return control to firmware. Unsigned rescue
is therefore a manual firmware-menu path with Secure Boot deliberately disabled,
not an automatic downgrade from the protected loader.
