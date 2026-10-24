# Desktop experiments with separate homes

`hosts/framework/environments.nix` is the registry. The primary `kde` entry uses
`novafs/nixos0/data/home`; `niri` uses `novafs/nixos0/data/home-niri`. An enabled non-primary
entry produces a named NixOS specialisation in each generation. Its desktop
module lives in `hosts/framework/desktops/`. All entries share the root and Nix
store, UID/GID, services and runtime secrets. This isolates desktop configuration
and user files, not system services or privileges.

Each entry declares a home dataset and a backup policy: `local` takes local
Arctern snapshots, `mira` also includes it in the existing Mira push job, `none`
excludes it from both. Disabled entries are excluded. The main home retains the
existing local retention, push job names, destination and transport policy.
Root and shared Nextcloud/tmp datasets stay excluded. Arctern must be activated
with the updated configuration before a new backup policy takes effect.

## Preparing an experiment

The laptop's Niri home was prepared on 2026-10-24 from
`novafs/nixos0/data/home@before-niri-20261024-122852`. KWin/Plasma session settings
were moved within the clone into
`~/.local/state/niri-migration/20261024-123149/`; browser profiles, credentials,
CLI tools, KWallet, Qt/GTK appearance preferences and personal files were kept.
The entry is enabled. The commands below describe preparation of a new home;
creation refuses to overwrite the existing Niri dataset.

These are explicit administrative steps, not rebuild side effects. The current
implementation does not create a laptop home or install a new firmware loader
until these steps are deliberately performed.

First use the new helper from an activated base configuration, or directly from
the working tree with a built manifest:

```sh
nix build .#nixosConfigurations.framework.config.system.build.frameworkEnvironments \
  --out-link result-environments
sudo uv run --offline --no-project --no-managed-python \
  modules/framework-environments/home.py \
  --manifest "$(readlink -e result-environments)" status
```

Choose either an empty home (clean Qt/GTK/KDE user settings):

```sh
sudo framework-home create niri --empty
```

or a clone of an explicitly chosen snapshot:

```sh
sudo zfs snapshot novafs/nixos0/data/home@before-niri
sudo framework-home create niri --from novafs/nixos0/data/home@before-niri
```

The direct working-tree invocation above also accepts `create niri --empty` or
`create niri --from ...` in place of `status`. A clone initially copies KDE and
Qt/GTK settings too; use an empty home for a clean comparison. Cloning does not
copy child datasets such as Nextcloud. It retains an origin dependency on the
snapshot. No promotion or origin cleanup is automatic.

The helper creates only the named filesystem, with `canmount=noauto` and
`mountpoint=/home`, and initializes the user's directory with the configured
UID/GID. It mounts the new home temporarily under
`/var/lib/framework-environments`, never over the live `/home`. It refuses an
existing target; rerunning cannot reset it. A preparation failure can leave the
new filesystem for inspection; the helper never destroys it during cleanup.

Set `entries.niri.enable = true`, then run `framework-rebuild boot` and reboot.
Select `Generation N · niri` in a zbm-rs version supporting specialisations.
Select the parent generation to return to KDE. The pinned zbm-rs source supports
this; updating the physical loader is a separate operation governed by the
existing signing/EFI procedure. Changing the flake lock alone does not update it.
Do not live-switch between configurations with different `/home` datasets.

`framework-rebuild` checks enabled home existence, mount properties, loaded keys
and shared checkout availability before signing or publishing boot files.
`switch` additionally requires the currently mounted home to match the target.
`build` performs manifest validation only, allowing preparation from another OS;
`boot`/`switch` perform runtime checks. Direct `nixos-rebuild` and direct
`switch-to-configuration` bypass this wrapper's preflight, so use the wrapper.
No rebuild creates, resets or deletes a dataset, and no tests run on each rebuild.

## Shared and independent files

Only the configured relative directories (`code/nixos-config` and
`code/nixos-secrets` by default) are bind-mounted from the primary home into the
experiment's home. The primary filesystem is mounted at
`/var/lib/framework-environments/primary-home` in experimental configurations.
The actual repositories remain in the primary home, owned by the user; edits,
commits and `/etc/nixos` always reach those same checkouts. No copy/move migration
or separate mutable checkout is involved. This also means the primary home is a
required filesystem for experimental boots, and is accessible at that service
path; this is not a security boundary. The private keys in `/var/lib` remain
outside home and outside the Nix store.

Nextcloud and tmp_zfs keep their existing explicit mounts at the same paths.
Everything else, including `.config`, `.local`, browser profiles, SSH configuration
and shell settings, belongs to the selected home. An empty home needs its own
user credentials/configuration; the helper does not copy them. System-wide
packages and environment variables still come from the selected NixOS closure.

Niri starts through greetd/tuigreet. It retains KWallet as the Secret Service
and secret portal provider, with PAM password unlock, so cloned application keys
remain available. Use the login password for the first login; a wallet with a
different password may prompt separately. Browser authorizations still require
verification in the actual session. The supplied basic configuration has
Mod+Return for Rio (Foot remains installed as a fallback), Mod+D for fuzzel and Mod+Shift+/ for help; it starts waybar
and mako. Customise `~/.config/niri/config.kdl` in that home as needed. Desktop,
fingerprint greeter, screen sharing and physical devices still need laptop
acceptance testing.

## Retiring an experiment

Disable the entry and rebuild for boot to stop producing new variants. Its home
is preserved. Old generations can still refer to it; booting one uses the home's
current contents, not the contents when that generation was built. Nix generation
rollback and ZFS snapshot rollback are separate operations.

`sudo framework-home status` shows mounts, clone origins, dependent clones and
references from retained system profiles (including their specialisations), the
current system and the booted system. Older generations without a manifest are
inspected through their fstab. Arbitrary root snapshots, external profiles and
unregistered boot environments are not exhaustively scanned. Keep disabled
entries in the registry while inspecting their homes.

There is no helper command for deletion, and no interception of `zfs destroy`.
Manually removing a home requires checking mounts, clone/snapshot dependencies
and any generations you intend to keep bootable. ZFS itself does not understand
NixOS generation references. The primary home is also the source of shared
checkouts and remains required by experiments.

## Tests

```sh
nix build .#checks.x86_64-linux.environments --no-link
nix build .#checks.x86_64-linux.environments-vm --no-link
nix build .#boot-environment-test --no-link
```

The fast check evaluates home selection, early mounting and backup policy, then
tests helper validation, no-overwrite behaviour, rebuild guards and retained
references. The integration check uses an encrypted disposable ZFS pool and
boots parent → variant → parent, exercising empty/clone preparation, independent
settings and shared checkouts/Nextcloud/tmp. No graphical desktop is started.
The last command is the generic upstream zbm-rs test, available explicitly rather
than duplicated in this repository's default checks. Existing specialised checks
remain. `nix flake check --no-build` evaluates checks; `nix flake check` builds all
checks on the current platform, reusing cached unchanged derivations.
