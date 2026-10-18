# Framework NixOS boot environment

NixOS unstable with KDE Plasma 6.8 on the Framework Laptop 13
(Intel Core Ultra Series 1).
Installs into `novafs/nixos0/root`, alongside Arch. NixOS uses native zbm-rs
generation discovery and owner-signed boot artifacts. The existing ZFSBootMenu
remains available as a fallback for Arch; zbm-rs is now the first firmware choice
after physical boot testing. No NixOS compatibility publisher for ZFSBootMenu
is installed.

## Layout

`novafs/nixos0/root` contains `/`, `/boot`, `/nix` and system state. The Nix
store deliberately shares the root snapshot so its system closure, profiles,
database, kernel and initramfs can be restored together. `/home` lives in
`novafs/nixos0/data/home`; restoring root does not restore user data.

All new mountable datasets use `canmount=noauto`. The root has `mountpoint=/`;
all datasets inherit `overlay=off`, `normalization=none`, `utf8only=off`, native
encryption from `novafs`. No dataset quota is imposed.
Other boot environments are not automatically mounted by NixOS.

Mounts are explicitly declared with `fileSystems`. `/home` is needed in initrd
before account activation creates home directories; otherwise `overlay=off`
rejects mounting the home dataset over those directories. Adding a dataset
requires a corresponding configuration change. An independent clone with its
own home needs updated root/home dataset names and a rebuilt generation before
its first boot.

## Build and verify

From Arch, where Nix is already installed:

```sh
export NIX_CONFIG='experimental-features = nix-command flakes'
nix build .#nixosConfigurations.framework.config.system.build.toplevel \
  --out-link result-framework --max-jobs 2 --cores 2
nix build .#installer --out-link result-installer
nix build .#checks.x86_64-linux.boot-environment --out-link result-vm-test
```

The native zbm-rs VM check uses a disposable encrypted ZFS disk. It installs
through the real NixOS bootloader hook, appends runtime secrets, checks early
home mounting and a normal user's home, tests publication failure with a missing
secret, updates a generation, and boots the original root's snapshot clone.
Separate zbm-rs signed-OVMF scenarios exercise protected NixOS and Arch handoff.
VM success does not establish physical laptop, firmware or TPM acceptance.

The `signed-modules` input is deliberately a local, public artifact at
`/var/lib/zbm-rs-public/framework-modules`. It contains owner-signed kernel,
ZFS and Insyde-recovery modules and an exact kernel-derivation manifest. Preserve
this input or regenerate it with `scripts/sign-framework-modules.sh`; private
keys are runtime files and never part of the input or Nix store.

## Install on the laptop

Commit the validated source first, then run `sudo scripts/install-framework.sh`.
It refuses to reuse an existing `novafs/nixos0`, limits itself to new datasets,
does not export the active pool, and leaves pool features, EFI files, firmware
entries and `bootfs` untouched. Root and `okhsunrog` password hashes and the ZFS
key are copied directly into the target's private files, never printed or
placed in Git/the Nix store. Existing user UID/GID is 1000.
The password-hash files in `/etc/nixos/secrets` are the declarative source for
future rebuilds; update them deliberately when changing passwords.

If installation fails, the datasets are preserved for inspection; the script
will refuse a second run. Do not destroy or overwrite them blindly.

After installation, manually choose the zbm-rs EFI entry, then select
`novafs/nixos0/root` and its prepared NixOS generation. Check
Wi-Fi, graphics, audio, brightness and suspend/resume on the actual laptop.

## KDE Plasma

Plasma Login Manager provides the graphical login, with Plasma as the default
session. The system includes Konsole, Dolphin, KDE authentication agent and
portals, Firefox, Neovim, PipeWire and Bluetooth. Neovim is the default editor;
`vi` and `vim` are aliases to it. Caps switches between US and Russian layouts.
The previous niri configuration remains in the source tree for reference.

`hosts/framework/daily-tools.nix` contains the first Arch migration package set:
Chrome/Firefox, AyuGram, KeePassXC, Nextcloud, LibreOffice, KDE utilities, editors,
Git, Rust/Python/JS/Go tools, Android/serial utilities and network diagnostics.
It enables direnv, nix-ld, Wireshark, Docker and libvirt/virt-manager, with explicit
user groups. Docker images/volumes, VMs, browser profiles and other user data are
not imported by adding these packages. Rustup toolchains and project development
libraries still need their own setup; the package list is not a universal SDK.
Zen, the personal Floppa/Arctern builds and corporate VPN/agent configuration
remain separate migration work. VK Teams is intentionally left to the browser.
CAD, Haskell, Julia, Logseq and Claude applications are excluded from this set.

`nixpkgs` follows `nixos-unstable`, pinned by `flake.lock`; refresh it with
`nix flake update nixpkgs`. The October 15, 2026 pin provides Plasma 6.8.0.
`system.stateVersion` stays at `26.05` to preserve existing state conventions.
The separately pinned, owner-trusted kernel and signed module tree remain
independent of the desktop package update.

The former niri desktop packages (Rio, Foot, fuzzel, waybar, mako, swaybg,
swaylock, Nautilus, xwayland-satellite, wl-clipboard, brightnessctl, playerctl
and pavucontrol) are no longer installed explicitly. Plasma supplies desktop,
clipboard, brightness, media and audio controls. The Rio and Rust overlay
flake inputs have been removed.

## Rebuild and recovery

On NixOS: `sudo nixos-rebuild boot --flake /etc/nixos#framework`. The upstream
zbm-rs NixOS module reads the standard Bootspec, copies its kernel and initramfs,
appends runtime secrets, and signs the resulting kernel, final initramfs and
exact native plan. The original store paths and Bootspec are never modified.
Prepared generations and owner authorizations live under `/boot/zbm-rs`.
Generation links are source-Bootspec-bound and restored on publication failure;
per-system GC roots retain their closures. Old bundles are retained for explicit
cleanup. There is no `/boot/nixos-current`, fake stable init path, kernel alias
or command line in ZFS properties.

Owner EFI/authorization and IMA keys live in root-only `/var/lib/secureboot`.
The provisioning also retains the enrolled PK/KEK/db hierarchy and owner GUID in
`/var/lib/sbctl`; `sbctl` is available for deliberate owner key management. Its
Arch-specific registered-file database is not imported. The PCR signing key is
`/var/lib/secureboot/pcr.key`, with its public key in `pcr-public.pem`. These are
runtime files outside Git and the Nix store. The existing native generation hook
uses `db.key` and `ima.key`; the PCR key is for explicitly preparing new loader
policies, not routine generation rebuilding. Arch helper scripts may still need
their filesystem/tool paths adapted before use in NixOS.
The OS kernel and all modules use the same explicit owner trust. A changed kernel
must match the signed module input exactly: the build stops if they differ.
After deliberately updating the kernel inputs, run
`sudo scripts/sign-framework-modules.sh` before rebuilding. The helper builds
the matching unsigned aggregate, signs and verifies a public copy outside Nix,
then refreshes only the local signed-module lock input. This is a key operation
outside derivations, not a disabled signature check or an unsigned fallback.

The OS retains native systemd TPM/SRK/NvPCR services and receives the installed
loader's signed PCR policy/public key through its runtime-secret appender.
Updating the EFI image requires refreshing this policy before preparing the next
OS generation. NixOS generation installation itself does not rebuild the loader,
change firmware entries, reset the TPM, or change Arch's boot files.

Root recovery does not roll back `/home`. A clone uses the same configured home
dataset; make a separate clone and update its configuration if home isolation is
needed. A trusted test snapshot must contain the complete prepared generation,
its authorization and matching OS PCR policy. Older pre-migration snapshots are
retained and are not silently authorized.

To recover from Arch, explicitly mount the desired root with
`sudo mount -i -t zfs -o zfsutil novafs/nixos0/root /mnt/nixos`, then its home at
`/mnt/nixos/home`. Unmount only those mounts when finished; do not export the
pool used by the running Arch system.
