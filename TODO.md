# TODO

- [ ] Install and physically validate the independent rescue lifecycle described
  in `docs/boot-recovery.md`. Cancellation-only guards, candidate/known-good
  publication, FAT tests and exact-artifact OVMF menu/input checks passed;
  the guarded source pin and build-closure retention are prepared here.
  Rescue is not installed on the new NVMe ESP. Install a verified baseline and
  test physical boot before relying on it; keep an external recovery copy.
- [ ] Verify the first physical NVMe boot after restoration, including KDE,
  niri, VPN, browser/VKey and existing credentials. Offline installation,
  standalone raw home restoration and the encrypted-storage VM check passed;
  see `docs/ssd-migration.md`.
- [ ] Build, owner-sign and physically validate authenticated hibernation under
  integrity Lockdown before enabling normal use on the laptop. The experimental
  Linux 7.2.9/ZFS 2.4.4 build through patch 0028 passed disposable VM acceptance:
  CRB/SHA-256 and TIS/dual-bank RAM restoration, creation of the next signed image,
  and the complete Secure Boot/enforced zbm-rs/PE/IMA/CMS target chain. Modified
  signature trailers, RAM-payload corruption and guest TPM clear were rejected
  before pool import; consumed attempts remained protected on the following boot.
  The CRB/SHA-256 interruption run restored the same RAM session three times,
  including retry after unavailable TPM, without losing its original boot ID.
  Empty-swap repair boot without TPM also passed, retaining integrity Lockdown
  and ordinary paging, with the explicit `systemd.tpm2_wait=0` repair argument.
  Patch 0028 authenticates the fresh NULL-primary context with the original
  provenance AK, fixing subsequent hibernation after RAM restore. It is a local
  experimental extension to Garrett's RFC, not an upstream-approved fix. See
  `nix/patches/hibernation-tpm-7.2.9/README.md` in zbm-rs. The main input advances
  independently of the guarded cancellation-only rescue baseline. The production
  kernel still needs a full build with this host's public trust certificates;
  VM signing artifacts are not production artifacts.
  Remove old generations and stale prepared artifacts after acceptance; intentional
  old-kernel downgrade research is out of scope. See `docs/boot-recovery.md` for
  the fixed architecture and remaining implementation work.
  Preserve resume-before-import ordering and explicit saved-session
  cancellation. Do not disable Lockdown or Secure Boot. The 48 GiB LUKS2 swap
  remains configured for ordinary paging; hibernation, hybrid sleep and
  suspend-then-hibernate remain disabled in this configuration.
- [ ] Investigate Orbit/osquery graceful shutdown: Orbit receives SIGTERM but
  remains alive until systemd kills it. The previous shutdown hit the full
  35-second timeout. Framework now limits `orbit.service` to 10 seconds as a
  workaround; inspect child-process shutdown and signal handling before
  replacing this workaround with a proper fix.
- [ ] Update the separately pinned AyuGram PLEngine package to use WebKitGTK
  2.54.2 or newer. The active NixOS generation currently retains WebKitGTK
  2.54.1 through `ayugram-plengine`; the system `webkitgtk_4_1` overlay does
  not affect this package because it comes from a separate flake input. See
  `hosts/framework/ayugram-plengine.nix` and `docs/ayugram-plengine.md`.
  Verify the package's runtime dependencies and behavior after updating. Do not
  rebuild AyuGram solely for this task until the update is wanted.
- [ ] Remove the temporary `nixpkgs-webkit` input and `hosts/framework/webkit.nix`
  override when the primary nixpkgs supplies the WebKitGTK animation fix
  (WebKit #321993), then verify Floppa uses the fixed version. Tangleaf has a
  separate temporary pin that should be removed independently.
