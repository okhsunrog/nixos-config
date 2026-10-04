#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
target=${1:-/mnt/nixos}
dataset=novafs/nixos0/root
[[ $EUID == 0 ]]
[[ $(findmnt -n -o SOURCE --target "$target") == "$dataset" ]]
for pair in 'mountpoint:/' 'canmount:noauto' 'overlay:off' 'normalization:none' 'utf8only:off' 'encryptionroot:novafs'; do
    property=${pair%%:*}
    expected=${pair#*:}
    [[ $(zfs get -H -o value "$property" "$dataset") == "$expected" ]]
done
[[ $(zfs get -H -o value org.zfsbootmenu:rootprefix "$dataset") == root=ZFS= ]]
[[ $(findmnt -n -o SOURCE --target "$target/home") == novafs/nixos0/data/home ]]
[[ $(readlink -e "$target/boot/nixos-current/system") == $(readlink -e "$repo/result-framework") ]]
cmp "$target/boot/vmlinuz-nixos" "$repo/result-framework/kernel"
[[ $(stat -Lc %a "$target/boot/initramfs-nixos.img") == 600 ]]
cmp /etc/zfs/zroot.key "$target/etc/zfs/zroot.key"
for user in root okhsunrog; do
    cmp <(getent shadow "$user" | cut -d: -f2) "$target/etc/nixos/secrets/$user-password-hash"
    [[ $(stat -c %a "$target/etc/nixos/secrets/$user-password-hash") == 600 ]]
done
# Resolve absolute /etc/static symlinks inside the installed root, not Arch.
system=$(readlink -e "$repo/result-framework")
awk '$1 == "novafs/nixos0/data/home" && $2 == "/home" && $3 == "zfs" && $4 ~ /(^|,)x-initrd.mount(,|$)/ { found = 1 } END { exit !found }' "$system/etc/fstab"
[[ $(chroot "$target" "$system/sw/bin/od" -An -tx1 /etc/hostid | tr -d ' \n') == 0cb1ba00 ]]
echo "Verified $dataset: layout, hostid, boot kernel, private initrd and copied secrets. Physical boot remains to be tested."
