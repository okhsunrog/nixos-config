# KDE and Niri with a shared home

Both boot entries use `novafs/nixos0/data/home`. The parent NixOS generation
starts KDE; the `niri` specialisation starts Niri and the Dux suite. ZFSBootMenu,
UID/GID, Nextcloud and tmp_zfs mounts are unchanged. Applications, credentials,
browser profiles, projects and ordinary configuration remain shared.

## Desktop exceptions

`framework.environments.homeMode` is `shared` on this laptop. The module also
retains `separate` for disposable experiments and older configurations. Shared
entries must agree on their dataset and backup policy. They do not mount the
primary home a second time or bind individual source checkouts.

`configProfiles` contains opt-in exceptions:

- `mutableFiles`: regular files saved and restored before login. The laptop
  selects only GTK3/GTK4 `gtk.css` and `settings.ini`. GTK bookmarks stay shared.
- `dconfKeys`: only six `/org/gnome/desktop/interface/` appearance keys are
  exchanged. Other applications retain their shared dconf database.
- `bindDirectories`: optional writable directories mounted from the selected
  profile. The laptop currently needs none. The VM exercises this facility.

Prepared state lives in `/home/.desktop-profiles/okhsunrog/`, owned by root with
mode 0700. Each desktop has its saved file contents and appearance keys. The
active files remain ordinary writable files at their usual paths, supporting
applications that save with atomic replacement. No logout hook or background
synchronizer is involved. Symlinks in mutable paths are rejected.

Before switching, the helper durably saves the outgoing state and an incoming
transaction. A power interruption is recovered by replaying the incoming
transaction before allowing login. Missing preparation, invalid paths or a
failed restore prevent user sessions and the greeter from starting. The boot
service is not restarted by a same-profile rebuild.

Niri-only state such as `~/.config/dms` can simply remain in the shared home:
Plasma does not consume it. KWin/Plasma settings also remain in place. Neither
whole `.config` nor whole GTK or dconf directories are isolated.

## Home Manager and session services

Both desktops activate Home Manager. `home/common.nix` establishes the common
user configuration; `home/kde.nix` and `home/niri.nix` select desktop-specific
managed files and services. Home Manager removes its obsolete managed links
when changing profiles; writable Dux includes, settings and other unmanaged
application data remain. Existing file collisions fail rather than being
silently renamed into backup files.

Dux Shell, Calendar, Files and Search start only in Niri. Dux Greeter remains
specific to that specialisation. Qt platform theme, terminal and cursor
variables are selected by the Niri system/session configuration, without
changing the shared default cursor or shell startup files. The Niri config
retains its writable generated includes and GUI preferences.

`kde-mimeapps.list` and `niri-mimeapps.list` select Dolphin and Dux Files
respectively, without rewriting the shared `mimeapps.list`. Portals are
selected in the NixOS desktop modules. Common autostart entries are preserved.

KWallet and VKey state stay shared. The Niri Secret Service waits for the
notify-ready `niri.service`, which imports the compositor environment, and
restarts on failure. Actual wallet unlock and TPM signing must still be checked
in the physical session; the encrypted-pool VM is not a TPM acceptance test.

## Explicit preparation and migration

A rebuild never prepares profile contents or imports files. First build the
manifest and review both dry runs, from the currently active KDE profile:

```sh
nix build .#nixosConfigurations.framework.config.system.build.frameworkEnvironments \
  --out-link result-environments
sudo uv run --offline --no-project --no-managed-python \
  modules/framework-environments/home.py --manifest result-environments \
  prepare-profiles --source kde=/home/okhsunrog --source niri=/PATH/TO/NIRI/HOME
sudo uv run --offline --no-project --no-managed-python \
  modules/framework-environments/home.py --manifest result-environments \
  migrate-settings --from /PATH/TO/NIRI/HOME
```

Add `--apply` separately after reviewing each plan. `prepare-profiles` refuses
to overwrite existing state. It reads the four mutable files and selected dconf
keys from each source; it does not replace any active files or dconf settings.
Its source for the current desktop must be the actual live user home.

`migrate-settings` imports only the enumerated Niri/Dux configuration, calendar
state and generated theme resources. It skips identical existing files and
refuses conflicts. It never merges browser databases, wallets, credentials,
repositories or arbitrary home contents. Source homes remain unchanged. Repos
must be reconciled with Git before retiring the old home.

After preparation, `framework-rebuild boot` can publish a new generation.
Reboot and select its parent KDE entry or Niri specialisation. Installation
and first physical reboot are separate from building and VM validation.

Profile layout changes require explicit preparation; a rebuild cannot silently
add new isolated paths. The current preparation command deliberately refuses
an existing profile root, so changing a prepared layout requires a reviewed
migration procedure rather than resetting it.

## Switching and rollback

`framework-home preflight` checks datasets, keys and prepared profile state.
For live activation it also compares the running desktop, home mode and
profile layout, then verifies configured bind mounts. Cross-desktop changes
require `boot` followed by reboot, even though the dataset stays the same.
The check is also registered with NixOS `system.preSwitchChecks`, covering
direct `switch-to-configuration` calls as well as the rebuild wrapper.
Same-profile rebuilds remain supported.

Version 1 manifests and separate-home preparation remain readable. The helper
never destroys datasets. Retain `novafs/nixos0/data/home-niri` and its snapshots
until the user explicitly retires them; old generations can still reference
that dataset. Older KDE generations lack the new Home Manager and profile
activation logic: they can boot, but see the last active shared appearance
files. Use the new KDE entry for routine desktop switching. Booting an old
system does not roll back shared application data or their database formats.

## Backups and tests

The one shared home retains Arctern local snapshots and Mira replication.
Dataset names are deduplicated per job. Conflicting backup policies for one
shared home are rejected. The retired Niri dataset is not a second active home
backup job; its existing snapshots are retained. Root, Nextcloud and tmp_zfs
policies are unchanged.

`checks.environments` covers module evaluation, manifests and profile helper
regressions, including interrupted restore and atomic GUI edits. The encrypted
`checks.environments-vm` boots both separate-home and shared-home systems,
checks profile mounts, Home Manager cleanup, common app data, Nextcloud/tmp,
live-switch refusal and repeated desktop changes. Actual graphics, Dux UI,
KWallet and VKey behavior still require physical-session verification.
