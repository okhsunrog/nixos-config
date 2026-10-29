# TODO

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
