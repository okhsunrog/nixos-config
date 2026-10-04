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
- Laptop installation completed in `novafs/nixos0/root` with its separate home.
  Kernel, private initramfs, hostid, dataset properties and copied secret files
  passed the post-install checks. Existing `bootfs` remains unset.
- Post-install checks were corrected to dereference the initramfs symlink and
  resolve `/etc/hostid` inside the target root.
- No physical NixOS boot, niri session or hardware validation has occurred.

Current build logs are `/tmp/nixos-framework-current.log` and
`/tmp/nixos-be-test-recovery.log`. Both builds finished successfully. The physical
installation log is `/tmp/nixos-framework-install.log`; the initial wrapper
stopped at its symlink-permission assertion, which was corrected and rerun.
