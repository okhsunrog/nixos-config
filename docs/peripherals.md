# Framework peripherals migrated from Arch

`hosts/framework/peripherals.nix` owns the device access rules and printer
queues. Local udev rules cover UNI-T/Voltcraft HID bridges, POWER-Z KM003C,
Ergot, thermal-cat cameras, the Vial keyboard, IQOS ILUMA and usbmon. Probe-rs rules come
from the `udevRules` source pinned by the existing Nixpkgs input, without
building the probe-rs tools themselves. The local uaccess rules run before
`73-seat-late.rules`; `plugdev` supplies their existing group fallback.
usbmon is loaded at boot and grants access to the existing `wireshark` group.
For already attached hardware, reconnect the device to apply its new rules.

The printer queues retain the old names and addresses:

| Queue | Transport | Defaults |
| --- | --- | --- |
| `Pantum_BM1800W` | IPP, `Pantum-38362E.local:631/ipp/print` | Default queue, A4, monochrome, one-sided |
| `Pantum_BM1800W_ManualDuplex` | JetDirect, `Pantum-38362E.local:9100` | A4, long-edge manual duplex |

The PPDs are preserved from the working Arch configuration, including the
manual-duplex vendor instructions. Neither queue is shared over the network.
Avahi and mDNS support resolve the existing printer hostname.

`packages/pantum-bm1800w.nix` patches the working x86-64
`ptm2300gdiFilter` 1.1.188 for NixOS. The archived filter and its license are
stored in the private Forgejo Generic registry; URL and SHA-256 are in
`packages/artifacts.json`. Authentication uses the existing runtime netrc and
never enters Git or derivations. The archive was extracted from the installed
Arch package after the official vendor download proved unavailable.

The system build, CUPS queue provisioning and the original seven udev files were
validated. Physical printing was not tested: at migration time the printer's
mDNS hostname did not respond. No test pages were submitted.

## Manual duplex orientation

Arch used a development snapshot of libcupsfilters (`ce65eb7455b5dedb08943a6d966f12bc4eaf3caa`,
packaged as `2.2.1.r28.gce65eb74`) with a local patch. Its new C PDF filter
unconditionally selected `sheet_back = "rotated"`, turning the reverse side
180 degrees in the Pantum manual-duplex workflow. The patch selects the driver
backside orientation through `cfGetBackSideOrientation()` instead. The owner's
paper test confirmed the Arch fix on 2026-10-08.

That exact patch is retained as `packages/libcupsfilters/duplex-orientation.patch`
for future upgrades. It is **not applied** to the current Nixpkgs libcupsfilters
2.1.1: that release has the older C++ PDF filter and does not contain the faulty
hard-coded rotation. It also does not implement all the newer filter's backside
transform options, so the original eight-case development-version test is not
a valid acceptance criterion for this older implementation.

`nix build .#checks.x86_64-linux.pantum-duplex` runs the actual Nixpkgs CUPS
`pdftopdf` executable and renders its PDF output with Poppler. It verifies front
and back marker positions for both binding edges, with the Pantum PPD's default
orientation and an explicit `Normal` option. No Arch library or `LD_PRELOAD` is
used. This detects a return of the reversed-back-page regression on upgrades;
it does not submit jobs or establish physical printer handling on NixOS.
All four combinations (eight rendered pages) passed on 2026-10-19 with the
same `cups-filters` package used by the running CUPS configuration.

The source of the development regression is visible in
<https://github.com/OpenPrinting/libcupsfilters/blob/ce65eb7455b5dedb08943a6d966f12bc4eaf3caa/cupsfilters/pdftopdf.c>.

Bluetooth pairing keys are mutable private state, not Nix expressions. The
Pixel Buds Pro 2 and IQOS records were copied from the same Arch adapter into
`/var/lib/bluetooth`, preserving root-only permissions. The already paired
Logitech Pebble and controller settings were not replaced. BlueZ was restarted
and all three devices were listed; the mouse record's hash was unchanged.
