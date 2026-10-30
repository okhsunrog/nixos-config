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
- [ ] Complete authenticated hibernation under integrity Lockdown before
  enabling it on the laptop. The zbm-rs LUKS2 guard and shared ZFS-unlock
  credential flow are implemented; an ordinary-kernel VM restored actual RAM
  through encrypted swap before importing ZFS. This does not validate signed
  hibernation under Lockdown. An opt-in Linux 7.2.9 port of Matthew Garrett's
  17-patch TPM-signature RFC passed full kernel/ZFS compilation in zbm-rs; VM
  runtime validation remains incomplete. EFI INITRD-table and moving E820-map
  fixes passed full rebuilds and handoff checks. One authenticated CRB/SHA-256
  RAM restore passed, but the next hibernation exposed a stale TPM NULL-primary
  context. Patch 0028 adds a fresh AK-attested context handoff; its affected
  objects compile and the full build/repeat-cycle checks are pending. See
  `nix/patches/hibernation-tpm-7.2.9/README.md` there. Complete EFI/TPM and kexec
  VM coverage for the shared patched loader/target kernel, image-tampering
  rejection, enforced loader-policy integration
  and physical testing before enabling normal use here. The source pins currently
  select the published guarded baseline, not the unaccepted experimental kernel.
  Boot-record v2 durable-attempt tracking passed ordinary RAM restoration;
  validate consumed-image failure/reboot and TPM-unavailable repair scenarios
  with the authenticated kernel too. Test SHA-256-only banks as on this laptop.
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
