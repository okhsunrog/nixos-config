{
  chatgpt,
  openssl,
  tpm2-tss,
}:
let
  version = "26.1013.40934";
  source = {
    inherit version;
    src = {
      url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_${version}_amd64.deb";
      hash = "sha256-PKWef5pmQbni+5rWgGg3hLWrgCb/dBj7ISoOvl3zodc=";
    };
  };
in
# Retain the desktop release's matching backend and code-mode host rather than
# substituting the older standalone release from this Nixpkgs revision.
(chatgpt.override { codex = null; }).overrideAttrs (old: {
  # Keep Nixpkgs' library fixups and writable bundled-plugin resource launcher.
  # Override its source metadata so version, download and update information agree.
  passthru = old.passthru // {
    sources = old.passthru.sources // {
      x86_64-linux = source;
    };
  };

  # The newer remote-control native module links against the TPM and crypto APIs.
  buildInputs = old.buildInputs ++ [
    openssl
    tpm2-tss
  ];

  # Prefer native Wayland locally, retaining the launcher's X11-session fallback
  # and allowing an empty NIXOS_OZONE_WL override to opt out.
  postFixup = old.postFixup + ''
    wrapProgram "$out/bin/chatgpt" --set-default NIXOS_OZONE_WL 1
  '';
})
