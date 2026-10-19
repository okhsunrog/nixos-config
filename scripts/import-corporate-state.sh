#!/usr/bin/env bash
# Import this laptop's existing enrollment; never enroll or change TPM objects.
set -euo pipefail
root=${1:-/mnt/nixos}
user=okhsunrog
[[ $EUID == 0 ]] || { echo 'Run with sudo.' >&2; exit 1; }
root=$(realpath -- "$root")
[[ $(findmnt -n -o SOURCE --mountpoint "$root") == novafs/nixos0/root ]]
[[ $(findmnt -n -o SOURCE --mountpoint "$root/home") == novafs/nixos0/data/home ]]
[[ $(findmnt -n -o SOURCE --target /opt/orbit) == novafs/arch0/root ]]
[[ $(findmnt -n -o SOURCE --target "/home/$user") == novafs/arch0/data/home ]]
marker=$root/var/lib/corporate-agent-migration/state-imported
[[ ! -e $marker ]] || { echo 'Existing import retained; refusing to replace enrollment state.' >&2; exit 1; }
destination=$root/home/$user
[[ -d $destination && ! -L $destination ]]
[[ ! -e $destination/.local/share/vkey-x509/tpm2_pkcs11.sqlite3 ]]
[[ ! -e $destination/.tpm2_pkcs11/tpm2_pkcs11.sqlite3 ]]
[[ ! -e $root/opt/orbit/osquery.db ]]

# Atomic snapshots avoid copying a live RocksDB database mid-write. Source
# agents, browser sessions and VPN connections remain completely untouched.
snapshot=corporate-import-$(date -u +%Y%m%dT%H%M%S)-$$
datasets=(novafs/arch0/root novafs/arch0/data/home)
snapshots=("${datasets[0]}@$snapshot" "${datasets[1]}@$snapshot")
mounted=("/.zfs/snapshot/$snapshot" "/home/.zfs/snapshot/$snapshot")
cleanup() {
    local status=$? path
    for path in "${mounted[@]}"; do
        if mountpoint -q "$path"; then umount "$path" || true; fi
    done
    for path in "${snapshots[@]}"; do
        if zfs list -H -t snapshot "$path" >/dev/null 2>&1; then zfs destroy "$path" || true; fi
    done
    exit "$status"
}
trap cleanup EXIT
zfs snapshot "${snapshots[@]}"
source_root=${mounted[0]}
source_home=${mounted[1]}/$user
[[ -s $source_home/.local/share/vkey-x509/tpm2_pkcs11.sqlite3 ]]
[[ -s $source_root/opt/orbit/secret-orbit-node-key.txt ]]
for directory in .local .local/share .local/share/vkey-x509 .pki .pki/nssdb .tpm2_pkcs11 .config; do
    install -d -m0700 -o1000 -g1000 "$destination/$directory"
done
rsync -a --chown=1000:1000 \
    --exclude=/openvpn --exclude=/libtpm2-pkcs11.so --exclude=/vkey-fp \
    --exclude=/barbos-tray --exclude=/barbos.ovpn.sh \
    "$source_home/.local/share/vkey-x509/" "$destination/.local/share/vkey-x509/"
rsync -a --chown=1000:1000 "$source_home/.pki/nssdb/" "$destination/.pki/nssdb/"
rsync -a --chown=1000:1000 "$source_home/.tpm2_pkcs11/" "$destination/.tpm2_pkcs11/"
if [[ -f $source_home/.config/kscreenlockerrc && ! -e $destination/.config/kscreenlockerrc ]]; then
    install -m0600 -o1000 -g1000 "$source_home/.config/kscreenlockerrc" "$destination/.config/kscreenlockerrc"
fi
install -d -m0755 "$root/opt/orbit"
rsync -a --exclude=/osquery.pid --exclude=/osquery.db/LOCK "$source_root/opt/orbit/" "$root/opt/orbit/"
for directory in /var/lib/nac-agent /var/cache/nac-agent; do
    install -d -m0700 "$root$directory"
    rsync -a "$source_root$directory/" "$root$directory/"
done
# Per-user legacy units would override the new declarative units after a home
# clone. Only these known vendor unit names are replaced by /etc/systemd/user.
for unit in barbos.service barbos-tray.service; do
    rm -f -- "$destination/.config/systemd/user/$unit" \
        "$destination/.config/systemd/user/graphical-session.target.wants/$unit"
done
install -d -m0700 "$(dirname "$marker")"
date -u +%FT%TZ > "$marker"
chmod 600 "$marker"
sync -f "$root"
echo 'Imported existing VKey/NSS, Orbit registration and NAC state. TPM objects and Arch services unchanged.'
