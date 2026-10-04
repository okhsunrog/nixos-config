# Validation status

Preparation started on 2026-10-04 from the running Arch boot environment.

- NixOS configuration evaluates with the pinned `nixos-26.05` input.
- Selected kernel: 6.18.55; OpenZFS: 2.4.4; niri: 26.04.
- Niri configuration passes `niri validate` (`checks.x86_64-linux.niri-config`).
- ShellCheck and Nix formatting pass.
- The encrypted-disk VM passed installation, the first kexec boot, preservation
  of the current bundle when its key is missing, and booting an updated
  generation, booting the original snapshot clone, and publishing from that
  clone. The complete test passed in 104.22 seconds. VM discovery uses by-path because
  its disposable disk has no serial/by-id link.
- Full laptop-system build completed; its closure is approximately 6.5 GiB.
- The host pool is healthy and has approximately 859 GiB available after cleanup.
- No laptop datasets have been created and no passwords/keys have been copied.
- No physical NixOS boot, niri session or hardware validation has occurred.

Current build logs are `/tmp/nixos-framework-current.log` and
`/tmp/nixos-be-test-recovery.log`. Both builds finished successfully.
