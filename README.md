# Framework NixOS boot environment

NixOS 26.05 with niri on the Framework Laptop 13 (Intel Core Ultra Series 1).
Installs into `novafs/nixos0/root`, alongside the existing Arch/Gentoo systems.
The existing ZFSBootMenu EFI application remains responsible for booting.

## Layout

`novafs/nixos0/root` contains `/`, `/boot`, `/nix` and system state. The Nix
store deliberately shares the root snapshot so its system closure, profiles,
database, kernel and initramfs can be restored together. `/home` lives in
`novafs/nixos0/data/home`; restoring root does not restore user data.

All new mountable datasets use `canmount=noauto`. The root has `mountpoint=/`;
all datasets inherit `overlay=off`, `normalization=none`, `utf8only=off`, native
encryption from `novafs`, and a 60 GiB hierarchy quota including snapshots.
Other boot environments are not automatically mounted by NixOS.

## Build and verify

From Arch, where Nix is already installed:

```sh
export NIX_CONFIG='experimental-features = nix-command flakes'
nix build .#nixosConfigurations.framework.config.system.build.toplevel \
  --out-link result-framework --max-jobs 2 --cores 2
nix build .#installer --out-link result-installer
nix build .#checks.x86_64-linux.boot-environment --out-link result-vm-test
```

The VM test uses a disposable encrypted ZFS disk, installs a minimal system,
boots it through a ZBM-style kexec handoff, publishes an updated generation,
then boots a clone of the original snapshot. It checks the actual root dataset,
the original system marker, hostid, home mount, and absence of foreign-BE mounts.
This is not yet an end-to-end UEFI/ZFSBootMenu or physical laptop test.

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

After installation, manually select `novafs/nixos0/root` in ZFSBootMenu. Check
Wi-Fi, graphics, audio, brightness and suspend/resume on the actual laptop.

## niri

The greetd/tuigreet login starts `niri-session`. Defaults are in
`hosts/framework/niri.kdl`: Super+Enter terminal, Super+D launcher, Super+E
files, Super+H/J/K/L focus, Super+Q close, Super+Escape lock, Caps switches
US/Russian. The system includes foot, fuzzel, waybar, mako, swaylock, Firefox,
PipeWire, Bluetooth and the recommended portals.

## Rebuild and recovery

On NixOS: `sudo nixos-rebuild boot --flake /etc/nixos#framework`. Reboot to use
the new generation. The publisher copies the kernel and initramfs, appends
runtime secrets, and atomically switches `/boot/nixos-current` to a matching
bundle. Only one kernel/initramfs pair is exposed to ZBM. The current closure
has a Nix GC root. Obsolete bundles under `/boot/nixos-generations` are retained
for inspection; they are not extra menu entries.

The ZBM property uses a stable `init=/boot/nixos-current/system/init` path.
The generation-specific store path lives in the filesystem snapshot. An initrd
generator mounts the dataset passed as `root=ZFS=...`, allowing snapshot clones
in the same pool rather than silently booting the original dataset.

Root recovery does not roll back `/home`. A clone uses the same configured home
dataset; make a separate clone and update its configuration if home isolation
is needed. ZBM command-line properties are not frozen in ZFS snapshots, so
generation-specific kernel parameter changes may need manual adjustment when
booting an old snapshot. The selected root and matching init closure are handled
by this module, but arbitrary historic parameter changes are not.

To recover from Arch, explicitly mount the desired root with
`mount -t zfs -o zfsutil novafs/nixos0/root /mnt/nixos`, then its home at
`/mnt/nixos/home`. Unmount only those mounts when finished; do not export the
pool used by the running Arch system.
