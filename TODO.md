# TODO

- [ ] Verify the first physical NVMe boot after restoration, including KDE,
  niri, VPN, browser/VKey and existing credentials. Offline installation,
  standalone raw home restoration and the encrypted-storage VM check passed;
  see `docs/ssd-migration.md`.
- [ ] Extend the zbm-rs hibernation guard to LUKS2 swap before enabling
  hibernation. The existing guard opens a plain swap PARTUUID directly; the
  loader must unlock and inspect the mapped swap before any writable ZFS
  import, and the target initramfs must resume from that same mapping before
  importing pools. Keep the saved-session cancellation UI and fail-closed
  checks. Test the encrypted path in a disposable VM before physical testing.
  The new 48 GiB encrypted swap is configured for ordinary paging meanwhile;
  hibernation, hybrid sleep and suspend-then-hibernate remain disabled.
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
