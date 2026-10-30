# TODO

- [ ] Implement and validate the independent rescue lifecycle described in
  `docs/boot-recovery.md`: cancellation-only hibernation guard, exact-artifact VM
  testing, retained known-good/candidate slots and build-closure retention.
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
  17-patch TPM-signature RFC is being built and tested in zbm-rs; see
  `nix/patches/hibernation-tpm-7.2.9/README.md` there. Complete EFI/TPM and kexec
  VM coverage, image-tampering rejection, enforced loader-policy integration
  and physical testing before updating the pinned loader/kernel inputs here.
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
