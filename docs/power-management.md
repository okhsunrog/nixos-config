# Framework 13 power management

`hosts/framework/power.nix` restores the Arch setup on the Framework Laptop 13
with Intel Core Ultra 5 125H: TuneD, tuned-ppd, and thermald.

TuneD's NixOS module enables UPower and disables power-profiles-daemon. KDE
PowerDevil continues to use the power profile D-Bus interface through tuned-ppd.
The pinned module's default mapping is:

| KDE profile | AC | Battery |
| --- | --- | --- |
| Power Saver | powersave | powersave |
| Balanced | balanced | balanced-battery |
| Performance | throughput-performance | throughput-performance |

The default profile is Balanced. Switching power sources selects the mapping
for the currently selected KDE profile; Performance is not automatically
changed to Balanced when unplugging the charger.

thermald uses `--adaptive` and the firmware's DPTF data, as the Arch service did.
There is no custom thermal configuration or bypass of CPU identification.

The firmware exposes only s2idle. No `mem_sleep_default=deep` override is used.
The historical `acpi_osi="!Windows 2020"` override is also removed: the pinned
nixos-hardware module limits that workaround to kernels below 6.8. These
command-line changes require a reboot; switching the system starts the power
management services immediately.

Check the active services and profile with:

```sh
systemctl status tuned tuned-ppd thermald
tuned-adm active
cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference
cat /sys/power/mem_sleep
```

Battery life, suspend power consumption, and resume must be measured on the
physical laptop. Correct service configuration alone does not establish an
improvement over power-profiles-daemon.

## Validation on 2026-10-19

TuneD 2.28.0, tuned-ppd, and thermald 2.5.12 started successfully. All three KDE
profiles were selected through the power profile D-Bus API and mapped to the
expected TuneD profiles. The previously selected Performance mode was restored.
The VPN and Arctern processes were not restarted.

The service PATH includes `which`, needed by virt-what to find its CPUID helper.
Without it, virt-what reports a missing helper despite that helper being present.

`tuned-adm verify` is not a clean pass on this Intel P-state system:

- TuneD applies Boost through Intel's `no_turbo` control, but its verification
  getter only checks the absent per-policy `boost` file. Turbo is enabled
  (`no_turbo=0`).
- With the performance governor, the kernel forces numeric EPP 0. Meteor Lake's
  named `performance` preference maps to 16, so the readback for 0 is `default`.
  The kernel rejects TuneD's subsequent attempt to write the named preference
  with EBUSY while this governor is selected. TuneD compares the strings and
  reports a mismatch even though the governor is applying its performance
  policy. See Linux `drivers/cpufreq/intel_pstate.c`,
  `intel_pstate_hwp_set`, `intel_epp_default`, and
  `show_energy_performance_preference`.

These verification limitations were not hidden by disabling verification or
changing the upstream profiles. The stock powersave profile also logs warnings
when its legacy Wi-Fi private-ioctl and EPB fallbacks do not apply; the EPP and
governor readbacks were checked separately.

TuneD's sysctl parser also logs errors for the three systemd default sysctl
patterns/exclusions in `/etc/sysctl.d/50-default.conf`. These are valid systemd
syntax; no systemd defaults were edited to accommodate TuneD's parser.
