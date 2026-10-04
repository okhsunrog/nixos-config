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
