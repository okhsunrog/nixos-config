# Arch to NixOS: home and VPN state

NixOS uses `novafs/nixos0/root` and `novafs/nixos0/data/home`. The latter is a
ZFS clone of `novafs/arch0/data/home@nixos-migration-20261019-044056`.
The 488 GiB home was not copied block by block: both datasets initially share
the snapshot's blocks, then independently allocate changed blocks. Both inherit
native encryption from `novafs`. Keep the origin snapshot while the clone uses it.

The old 14 MiB NixOS home was overlaid onto the clone to retain the existing
NixOS-specific setup, then renamed to
`novafs/nixos0/data/home-before-migration-20261019-044056`. It may be removed
after physical acceptance. The Arch home remains untouched.

`novafs/nextcloud` and `novafs/tmp_zfs_home` remain shared datasets mounted at
`~/Nextcloud` and `~/tmp_zfs`. They are not included in the home clone.

The clone preserves SSH/GPG keys, Codex authentication, user tools, KDE settings
and browser profiles. No Home Manager module is enabled. Nix-specific executable
paths in the cloned shell environment were corrected, as was the VKey launcher.
Browser process locks were removed only in the clone. Zen's existing
`Default (release)` profile is now the general default, matching the original
installation's active profile. Nix's Zen wrapper uses legacy shared-profile
selection, so a different store path does not select a new empty profile.
The installed browser is at least as new as the Arch profile's last version.
Websites can still require another login; copying a profile cannot guarantee
that a remote session remains accepted.

Floppa is built natively from a GitHub input pinned in `flake.lock`.
Its CLI, GUI, polkit helper and systemd units come from the upstream project's
NixOS module. API deployment metadata is checksum-pinned in the private Forgejo
registry; it contains no session or access token.

Floppa, Tangleaf and Arctern use their upstream Crane recipes. Their compiled
Rust dependency caches are separate from application/frontend source inputs.
Tangleaf's packaged desktop launcher replaces the user override pointing at an
Arch developer build. Its data/profile still comes from the home clone.
Arctern is installed without enabling its daemon: existing replication, prune
jobs and daemon state need a separate migration before starting it.
KeePassXC is installed through `daily-tools.nix`; its databases remain user data.

Five persistent files were copied byte-for-byte from a consistent root snapshot
to `/var/lib/floppa-vpn`: `settings.json`, `vpn-config.json`,
`server-session.json`, `runtime.json`, `endpoint-cache.json`. The target directory
is root-owned mode 0700, files mode 0600. Runtime intent was preserved, including
the Connect on boot preference. `rollback.json` and `network-rollback-v1` belong
to the old operating system's applied routes and must not be imported.
User-side Floppa state arrived with the home clone. Runtime secrets are not Git
configuration; protect/backup them through encrypted ZFS snapshots. Activation
does not overwrite mutable session and user preference files.

The generated boot generation must be published and signature-verified before
reboot. VM checks cover service/standalone operation and socket marking;
physical Wi-Fi, VPN endpoint access, TPM, browser login and restored desktop
session still require testing after booting NixOS. The Arch BE remains available.

## Removed Arch-specific user integration

The cloned home now uses `/run/current-system/sw/bin` for GitHub's credential
helper, Nextcloud autostart, Konsole's Bash profiles and existing user units
(SSH agent, JobAI tunnel and Realty Aggregator). Konsole's theme scripts use
`qdbus`; GLib's `gdbus` and Qt tools are installed. EasyEffects is installed for
its existing autostart. Stale Arch PipeWire enablement links were removed; the
NixOS PipeWire module owns its units. Personal project services retain their
mutable environment files; their application/build dependencies still belong
to the individual projects' development environments.

User desktop overrides for absent applications and the old Floppa debug build
were removed, and MIME associations now refer to installed launchers. Working
home-installed applications, profiles, source trees and developer caches were
kept. `start-vpn` and `stop-vpn` now invoke Floppa rather than the obsolete
`wg-rotator` service.

Three broken uv environments (`grip`, `sherlock-project`, `zev`) were recreated
on the existing managed Python 3.13, keeping their application versions.
Former user-pip command line tools (`av`, `onnxruntime`, `huggingface-hub`,
`typer`, `ctranslate2`) now have isolated uv tool environments instead of Arch
Python shebangs. Hugging Face keeps its prior version with the CLI dependencies
and MCP extra; use `hf`, since that release's `huggingface-cli` is deprecated.
System `uvx` and `git-filter-repo` replace the old pipx entry points.
Native D-Bus/introspection libraries for migrated bindings are supplied through
`programs.nix-ld.libraries`. No generic `/usr/bin/python` compatibility link was
added. Package import checks do not establish that every optional SDK,
converter backend or physical device integration works.

## Firefox outside both VPNs

`services.novpn` is implemented in `modules/novpn`. It retains the original
host's cgroup-based design: `novpn.slice` sockets get mark `0xca6c`, rules 90/91
route them through table 51821, and that table contains the lowest-metric live
physical default plus its connected LAN prefixes. Tunnel defaults and corporate
split routes are not copied into this table. IPv4 and IPv6 are handled
separately; an unreachable default prevents falling back into a VPN when no
physical default exists. Only the dedicated nftables table is replaced, without
flushing Firewalld's or Floppa's tables.

The declarative NetworkManager dispatcher refreshes the routes on link, DHCP,
reapply and VPN events. `novpn-ff` starts the user anchor and uses a narrowly
scoped passwordless sudo rule to refresh the root unit before creating browser
sockets, so nftables resolves the current cgroup inode. The old home alias,
script and anchor definitions no longer override this integration.

The existing Firefox `novpn` profile keeps its AdGuard DoH endpoint/bootstrap
and now sets `network.trr.mode = 3` and `network.proxy.type = 0` in `user.js`.
DNS is therefore performed by the marked browser without fallback to the
system resolver outside its cgroup. An unavailable DoH endpoint causes DNS
failure in this profile rather than silently using the VPN's resolver.

`nix build .#checks.x86_64-linux.novpn` exercises IPv4/IPv6 HTTP, full-tunnel
policy rules, corporate split defaults, a physical default-route change, loss
of the physical default, and cgroup recreation in disposable VMs with Firewalld.
Actual Firefox GUI operation remains a check after booting NixOS.
