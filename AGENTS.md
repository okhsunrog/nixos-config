# Repository instructions

This is the personal NixOS configuration for a Framework Laptop 13 Intel Core
Ultra Series 1, installed as a new BE in an existing encrypted ZFS pool.

- Keep `nixpkgs` and `nixos-hardware` pinned with `nix flake lock`/`nix flake update`.
- Run `nix fmt`, ShellCheck on shell scripts, and the relevant flake checks.
- Boot integration changes require the disposable encrypted-pool VM test.
- Keep `/nix` within root so ZBM snapshots include their complete system closure.
- Preserve foreign BEs, pool features, `bootfs`, EFI files and firmware entries.
- Use tracked sessions for long builds/VMs; never launch an untracked shell job.
- Never put password hashes or ZFS keys in Git or the Nix store, or print them.
- Distinguish module/VM tests, actual ZBM firmware boot, and physical hardware checks.
- Use clear commits without generated-by, assistant or session attribution.
- Never publish review comments or replies; draft them in chat instead.
- Keep the working repositories in the owner's home, owned by the normal user.
  Git commits/pushes use that user's credentials; do not duplicate SSH keys into
  root's account. `/etc/nixos` links to the working configuration.
- `host-secrets` is a pinned private Git input containing SOPS ciphertext only.
  The age private key is root-owned mode 000 at `/var/lib/sops-nix/key.txt`, with
  an independent owner-managed password-manager backup. Never add it to Git.
- Private package downloads use the root-only runtime netrc. Never embed tokens
  or enrollment credentials into Nix expressions, URLs, derivations or archives.
- Keep Home Manager out of this migration until explicitly requested.
