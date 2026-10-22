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
this input or regenerate it with `scripts/rebuild-framework.sh`; private
keys are runtime files and never part of the input or Nix store.

## Install on the laptop

Commit the validated source first, then run `sudo scripts/install-framework.sh`.
It refuses to reuse an existing `novafs/nixos0`, limits itself to new datasets,
does not export the active pool, and leaves pool features, EFI files, firmware
entries and `bootfs` untouched. The ZFS key and a separately restored age key
are copied directly into the target's private files, never printed or placed
in Git/the Nix store. Existing user UID/GID is 1000. Password hashes now come
from the SOPS-encrypted, pinned private `host-secrets` input, before user setup.
The former plaintext password-hash files in `/etc/nixos/secrets` are no longer
used; the old installed source copy is removed when linking the working tree.

See [secrets and private artifacts](docs/secrets-and-artifacts.md) for the two
Forgejo repositories, package authentication, bootstrap and signing-key recovery.

The working Git repositories live in `/home/okhsunrog/code/nixos-config` and
`/home/okhsunrog/code/nixos-secrets`, owned by UID/GID 1000. `/etc/nixos` is a
symlink to the first repository, not a second source copy. Edit/commit/push as
the normal user and use sudo only for provisioning secrets or applying the
system. Root uses a read-only Forgejo token, not copied user SSH keys.

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

`hosts/framework/daily-tools.nix` contains the first Arch migration package set:
Chrome, AyuGram, KeePassXC, Nextcloud, LibreOffice, KDE utilities, editors,
Git, Rust/Python/JS/Go tools, Android/serial utilities and network diagnostics.
It enables direnv, nix-ld and Wireshark.
`hosts/framework/virtualisation.nix` configures Docker and libvirt/virt-manager,
including user groups, bridge MTU and the libvirt credential workaround.
`desktop.nix` configures Plasma and audio; `storage.nix` contains the ZFS layout
and its boot dependencies. Firefox and its VKey integration are enabled by
the corporate module. Docker images/volumes, VMs, browser profiles and other user data are
not imported by adding these packages. Rustup toolchains and project development
libraries still need their own setup; the package list is not a universal SDK.

External monitor brightness uses PowerDevil's DDC/CI support. `peripherals.nix`
enables `hardware.i2c` to load `i2c-dev` and grant the local session access to
the I2C devices, and installs `ddcutil` for diagnostics. DDC/CI must also be enabled
in the monitor's own settings. Check detection with `ddcutil detect` and read
brightness with `ddcutil --bus BUS getvcp 10`.

Docker's default bridge and newly created user-defined bridges use MTU 1280,
matching the Floppa tunnel. At MTU 1500, forwarded TCP connections advertised
MSS 1460 and stalled while downloading HTTP responses through the tunnel;
host networking worked because host connections used the tunnel's smaller MTU.
Both `mtu` and `default-network-opts` are set in the daemon configuration
([Docker reference](https://docs.docker.com/reference/cli/dockerd/#default-network-options)).
Existing user-defined networks retain the settings from their creation and
must be recreated to pick up a changed default. Normal Docker builds use
their default network; no `--network=host` option is required.

Zen and VS Code are also installed. Floppa and Arctern are native
packages built with Crane from GitHub inputs pinned in `flake.lock`.
Tangleaf is built incrementally from its local checkout using its dev shell
and user desktop launcher, independently of NixOS rebuilds. Arctern is enabled
by `hosts/framework/arctern.nix`, with its replication identity decrypted by
SOPS. NixOS home is replicated to Mira; Arch backup history is preserved. See
[`docs/arctern-migration.md`](docs/arctern-migration.md) for the incremental
cutover. Corporate VPN/agent setup is described in
[`docs/corporate-workstation.md`](docs/corporate-workstation.md).
VK Teams is intentionally left to the browser.

AyuGram uses the pinned Linux PLEngine fork, with native plugins built alongside
the client. Its package and per-user plugin links are declared in
`hosts/framework/ayugram-plengine.nix`; see
[`docs/ayugram-plengine.md`](docs/ayugram-plengine.md).
CAD, Haskell, Julia, Logseq and Claude applications are excluded from this set.

Starship is installed for the existing user Bash configuration. Flyline uses
the official 1.10.0 release with its published archive checksum, not the older
personal fork. Its Nix-patched loadable library is enabled for interactive Bash
outside `TERM=linux`; `FLYLINE=0 bash` retains plain readline. Existing user
Starship configuration is left to the home migration.

`nixpkgs` follows `nixos-unstable`, pinned by `flake.lock`; refresh it with
`nix flake update nixpkgs`.
`system.stateVersion` stays at `26.05` to preserve existing state conventions.
The separately pinned, owner-trusted kernel and signed module tree remain
independent of the desktop package update.

The pinned nixpkgs includes the
[upstream NixOS mitigation for the October 2026 eMudhra CA compromise](https://github.com/NixOS/nixpkgs/pull/576390),
so no local CA blacklist is needed. The system CA bundle explicitly distrusts
`Comodo AAA Services root`, `emSign ECC Root CA - G3`, `emSign Root CA - C1`
and `emSign ECC Root CA - C3`.
Applications with embedded trust stores still require their own security updates.

## Rebuild and recovery

The Framework host enables the [corporate workstation integration](docs/corporate-workstation.md):
VKey/Barbos, split DNS, TPM access, confined NAC/Orbit, read-only D-Bus, audit and
script archival. Issued keys and registration state stay outside the Nix store.
The corporate VM check uses only disposable agents and a virtual TPM.

On NixOS, run as your normal user:

```sh
cd ~/code/nixos-config
./scripts/rebuild-framework.sh          # prepare the next boot; keep this session
./scripts/rebuild-framework.sh switch   # also activate the configuration now
./scripts/rebuild-framework.sh build    # prepare/build only; do not install
```

Once this configuration is activated, `framework-rebuild` is the same command
for the working repository at `/etc/nixos`; it can be called from any directory.

The command builds public signing plans and the unsigned kernel/module outputs
using your own Nix cache and Git credentials. It elevates only the module-signing
step and system installation. It refreshes only `signed-modules` in `flake.lock`,
then builds the complete system before changing the system profile. Normal
configuration edits reuse the cached signed modules; changes to any module
source, kernel or trust/signing inputs invalidate that cache. Build options can
be passed after `--`, for example `boot -- --max-jobs 2 --cores 2`.

It also builds the main Framework EFI image, signs its IMA policy and modules,
and signs/verifies the final UKI outside the store. Prepared EFI images are
cached under `/var/lib/zbm-rs-signing/loader`. The OS PCR policy is extended for
the new UKI and the currently installed UKI before preparing the new generation;
existing signatures remain available. Each system retains its exact EFI signing
plan and build inputs. The bootloader hook installs that prepared EFI only after
generation preparation succeeds, replacing `EFI/zbm-rs/zbm-rs.EFI` on the explicit
ESP. Existing firmware entries and their order are preserved. `build` prepares
the image and policy but does not write EFI files or change the system profile.

### Independent rescue loader

`zbm-rs (rescue)` uses `EFI/zbm-rs/rescue.EFI`, an unsigned image with
`security.mode = "off"`, TPM support disabled in the loader and an ordinary kernel
without forced lockdown/module-signature enforcement. Its source revision and
Nixpkgs are pinned independently through `zbm-rescue`; ordinary system/input
updates do not advance that source or overwrite its installed EFI file.

Install or deliberately refresh it as the repository owner:

```sh
framework-rescue-update --max-jobs 2 --cores 2
```

To advance rescue, explicitly change the revision in `zbm-rescue.url`, refresh its
lock with `nix flake update zbm-rescue`, and test/install it separately after the
main loader has passed a physical boot. It is never updated by
`framework-rebuild`. To use rescue, disable firmware Secure Boot temporarily and
choose its separate EFI entry. The installer refuses to accept a signed rescue
file. Recovery offers the loader shell and manual pool unlocking; it does not
promise that TPM-dependent services inside NixOS work in this mode. Re-enable
Secure Boot after repair. The existing ZFSBootMenu and foreign EFI files remain.

### Signing and generation publication

Signing uses root-only `/var/lib/zbm-rs-signing`, retains immutable public outputs
and the public plan with Nix GC roots, and atomically replaces the real
public-input directory. The plan also retains `kernel.dev` and unsigned modules,
so deleting ordinary result links and running GC does not discard this build
cache. Old signing-cache roots are retained until explicitly removed by the owner.
The manifest binds the result to both the exact kernel and unsigned module-tree
store paths. This catches a changed Insyde/ZFS module even with the same kernel
ABI. An existing legacy tree can be adopted without re-signing only after every
module's decompressed payload and signature, and all metadata, are checked.
Private key material never enters Nix expressions, plans, outputs or build sandboxes.
The script does not update dependencies or commit the resulting lockfile; review
and commit it with your intended configuration change. A failed build leaves the
installed system alone. A failed activation restores the profile pointer where
possible but is not a promise to undo every partially applied runtime change.

The upstream
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
uses `db.key` and `ima.key`; the preparation step uses the PCR key when authorizing
the main loader's measurement. Arch helper scripts may still need
their filesystem/tool paths adapted before use in NixOS.
The OS kernel and all modules use the same explicit owner trust. A changed kernel
must match the signed module input exactly: the build stops if they differ.
After deliberately updating the kernel inputs, use the same
`./scripts/rebuild-framework.sh` command. Its privileged half consumes only a
completed immutable signing plan; it performs no Nix evaluation, Git access or
lockfile edits. A direct `nixos-rebuild` remains possible when the signed input
already matches, but does not orchestrate module preparation. This is a key
operation outside derivations, not an unsigned fallback.

The OS retains native systemd TPM/SRK/NvPCR services and receives the installed
loader's signed PCR policy/public key through its runtime-secret appender.
Updating the EFI image requires refreshing this policy before preparing the next
OS generation. EFI construction and signing happen in the preparation step;
generation installation consumes that prepared signed file. Neither step resets
the TPM or changes Arch's boot files.

Root recovery does not roll back `/home`. A clone uses the same configured home
dataset; make a separate clone and update its configuration if home isolation is
needed. A trusted test snapshot must contain the complete prepared generation,
its authorization and matching OS PCR policy. Older pre-migration snapshots are
retained and are not silently authorized.

To recover from Arch, explicitly mount the desired root with
`sudo mount -i -t zfs -o zfsutil novafs/nixos0/root /mnt/nixos`, then its home at
`/mnt/nixos/home`. Unmount only those mounts when finished; do not export the
pool used by the running Arch system.

The [Arch home migration notes](docs/arch-home-migration.md) describe the
independent home clone, shared datasets, Zen profile and imported Floppa state.
