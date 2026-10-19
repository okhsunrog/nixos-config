# Corporate workstation on NixOS

`hosts/framework/corporate.nix` enables `modules/corporate`. Programs come from
the version/hash-pinned private Forgejo artifacts. Registration credentials are
decrypted by SOPS at runtime; neither the TPM database nor VPN profiles belong
in the public configuration or Nix store.

## Programs, state and privileges

| Component | Immutable configuration/program | Mutable state |
| --- | --- | --- |
| VKey client | `packages/corporate.nix`, `vkey-x509-client-linux` | Existing issued certificates and TPM objects; bootstrap is not run by activation |
| VKey provider, OpenVPN, fingerprint helper, tray | Exact hashed go:embed payloads from the pinned vendor client, with Nix ELF fixups | `~/.local/share/vkey-x509` and NSS browser databases |
| Barbos | Declarative user units in `/etc/systemd/user`; manually started VPN | Private `barbos.ovpn`; tray starts with the graphical session |
| OpenVPN privilege | Root-owned `/run/wrappers/bin/vkey-openvpn`, `CAP_NET_ADMIN`, executable by `tss` | No capability on a user-writable binary or the read-only Nix store |
| NAC | Enforced `corporate-nac` AppArmor profile and systemd sandbox | `/var/lib/nac-agent`, `/var/cache/nac-agent`, `/var/log/nac-agent` |
| Fleet/Orbit | Enforced `corporate-orbit` profile; pinned initial binaries | `/opt/orbit`: registration, osquery database and signed updater cache |
| Script archive | `agent-script-archive` built from tracked Go source | Root-only `/var/lib/corporate-agent-archive` |

The provider's conventional `~/.tpm2_pkcs11/tpm2_pkcs11.sqlite3` path and the VPN
database in `~/.local/share/vkey-x509` are preserved separately. The existing
Arch copies differ: migration must not silently merge them. Runtime setup
creates stable program links without modifying either database or creating TPM
keys. It registers the provider in Chromium's NSS
database and existing Firefox/Zen profiles. Firefox also has a declarative
SecurityDevices policy for new profiles. Browser management notices can result
from that policy; no browser extension or remote browser administrator is added.
After importing additional browser profiles, rerun `vkey-runtime-setup` before
opening the browser. Do not run NSS initialization over an existing database.

The stock `security.tpm2.pkcs11` provider is deliberately not substituted for
VK's provider: the vendor payload also implements fingerprint unlock. `tss`
membership and `tpm2-abrmd` are enabled. Existing TPM objects are retained. A new
OS boot, hardware access and actual certificate signing still require physical
acceptance; a VM cannot establish compatibility of this laptop's issued keys.
Fingerprint enrollment is optional. With `fprintd` enabled, use the vendor
`vkey-fp status`/`enable` workflow after confirming PIN-based login. No PIN is
embedded in Nix expressions, unit files or Git.

Orbit's normal signed updates remain enabled. Initial programs are patched Nix
packages; subsequently downloaded ELF programs use `nix-ld`, with its loader
variables explicitly supplied to the service. They stay in the confined mutable
cache. This is not a claim that every future corporate binary is compatible.
Shell/Python interpreter aliases needed by vendor scripts are provided only in
the agent mount namespaces, not as host-wide FHS modifications.

## DNS and firewall

NetworkManager uses systemd-resolved. The OpenVPN up hook assigns pushed DNS
servers to that tunnel, adds only the corporate routing suffixes in
`/etc/openvpn/barbos-dns-domains`, and sets `DefaultRoute=no`. It refuses an empty
suffix list and strips a pushed catch-all. The suffixes are `vk.team`,
`vkteam.ru`, `corp.mail.ru`, `devmail.ru`, `bid.max.ru`, `assistant.mail.ru`.
Deleting the tunnel removes its link-scoped DNS settings. The existing private
VPN must continue supplying its own DNS/routing configuration; this module does
not install or reconfigure Floppa.

Only this user's `resolvectl` command is permitted passwordless through sudo,
using the actual Nix systemd executable. Firewalld is the NixOS firewall backend
with nftables and loose reverse-path checking for coexistence of tunnels. NAC's
compatibility CLI translates its runtime `--get-target` query to a read-only
FirewallD D-Bus query; values are real firewall state, not fabricated compliance.

## Confinement and evidence

Agents cannot read private homes (except NAC's read-only KDE screen-lock file),
`/mnt/nfs`, ZFS unlock material, SOPS/signing keys, private VPN configuration,
runtime secrets, process environments or the archive. The real system/user
D-Bus sockets are hidden. A filtered proxy exposes read-only hostname, login
and firewall facts, not mutation calls. Home protection additionally uses
systemd mount namespaces. Writes are limited to each agent's state/log/temp
directories. Remote children inherit the AppArmor profile and privilege limits.

Audit selects `corporate-nac`/`corporate-orbit` by AppArmor's `subj_role` and
records exec/fork events, including children changing UID. The script listener
blocks file opens on a separate 256 MiB tmpfs and archives Fleet-shaped
`fleet-*/script` files, synchronizing contents and metadata before allowing the
reader to proceed. Failure denies that open. Agents depend on the listener and
D-Bus proxy and stop if either goes down.

This is evidence collection, not universal recording or content approval:
capture proves a file open, not execution; correlate exec records. Shell builtins,
code elsewhere, memfd, interpreter imports and later rewrites are not fully
reconstructed. Listener shutdown releases pending fanotify requests before
systemd completes stopping dependents, so this is not an atomic execution lock.
Audit rotates eight 64 MiB files; the script archive has no automatic deletion.
Keep these root-only because command arguments/scripts may themselves be private.

```sh
sudo agent-audit status
sudo agent-audit list
sudo agent-audit show CAPTURE_ID
sudo agent-audit commands
sudo agent-audit forks
sudo agent-audit apparmor
```

## Migration and acceptance

On Arch with the two NixOS datasets mounted at `/mnt/nixos`, run
`sudo scripts/import-corporate-state.sh /mnt/nixos` once. It takes atomic,
temporary ZFS snapshots of the source root/home so active RocksDB/SQLite files
are copied consistently, imports existing VKey/NSS and Orbit registration, and
removes only its own temporary snapshots. It does not stop the Arch VPN, enroll
the device, change TPM objects, or copy secret bytes into build artifacts. It
refuses to replace an already imported target token/database. Existing browser
profiles are part of the separately agreed full home clone, not this state copy.
Do not reintroduce legacy `~/.config/systemd/user/barbos*.service` files when
cloning the rest of home: they would override `/etc/systemd/user` units.

Build and install the system as a new signed NixOS boot generation, not with
`switch` on the running Arch host. After booting that generation:

```sh
systemctl status tpm2-abrmd systemd-resolved firewalld nac-agent orbit
sudo agent-audit status
systemctl --user status vkey-runtime-setup barbos-tray
systemctl --user start barbos
systemctl --user status barbos
resolvectl status
```

Confirm TPM certificate use with the saved PIN, corporate DNS/service access,
ordinary Internet access through the private VPN, and fresh NAC portal checks.
The VM test uses only disposable local agents/state and a virtual TPM; it checks
ELF loading, user TPM access, OpenVPN capability, profile denials, script archive,
exec audit, filtered D-Bus, DNS configuration and dependent shutdown. It does not
enroll with corporate servers or prove corporate acceptance of NixOS policy
checks. Unsupported distribution checks must be reported rather than spoofed.
