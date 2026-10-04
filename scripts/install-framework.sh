#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
pool=novafs
prefix=$pool/nixos0
target=/mnt/nixos

if [[ $EUID != 0 ]]; then
    echo "Run with sudo after the VM test passes." >&2
    exit 1
fi
if [[ $(cat /sys/class/dmi/id/product_name) != 'Laptop 13 (Intel Core Ultra Series 1)' ]]; then
    echo 'This script is only for the Framework Core Ultra Series 1 laptop.' >&2
    exit 1
fi
system=$(readlink -e "$repo/result-framework")
installer=$(readlink -e "$repo/result-installer")
test_result=$(readlink -e "$repo/result-vm-test")
[[ -n $system && -n $installer && -n $test_result ]]
git -c safe.directory="$repo" -C "$repo" diff --quiet
git -c safe.directory="$repo" -C "$repo" diff --cached --quiet
[[ $(hostid) == 00bab10c ]]
[[ $(zfs get -H -o value encryptionroot "$pool") == "$pool" ]]
[[ $(zfs get -H -o value keystatus "$pool") == available ]]
[[ -r /etc/zfs/zroot.key ]]
if zfs list -H "$prefix" >/dev/null 2>&1; then
    echo "Refusing to reuse $prefix. Inspect an interrupted installation manually." >&2
    exit 1
fi
if mountpoint -q "$target" || [[ -d $target && -n $(find "$target" -mindepth 1 -maxdepth 1 -print -quit) ]]; then
    echo "Target $target must be empty and unmounted." >&2
    exit 1
fi
available=$(zfs get -Hp -o value available "$pool")
if (( available < 40 * 1024 * 1024 * 1024 )); then
    echo 'Less than 40 GiB available; free space before installing.' >&2
    exit 1
fi
default_before=$(zpool get -H -o value bootfs "$pool")

zfs create -u -o mountpoint=none -o canmount=off -o overlay=off \
    -o normalization=none -o utf8only=off -o acltype=posixacl -o xattr=sa \
    -o compression=zstd -o quota=60G "$prefix"
zfs create -u -o mountpoint=/ -o canmount=noauto "$prefix/root"
zfs create -u -o mountpoint=none "$prefix/data"
zfs create -u -o mountpoint=/home -o canmount=noauto "$prefix/data/home"
mkdir -p "$target"
mount -t zfs -o zfsutil "$prefix/root" "$target"
cleanup() {
    # Only our new BE's mounts. Never export the running host pool.
    if mountpoint -q "$target/home"; then umount "$target/home"; fi
    if mountpoint -q "$target"; then umount "$target"; fi
}
trap cleanup EXIT
mkdir "$target/home"
mount -t zfs -o zfsutil "$prefix/data/home" "$target/home"
install -d -m 0700 "$target/etc/zfs" "$target/etc/nixos/secrets"
install -m 000 /etc/zfs/zroot.key "$target/etc/zfs/zroot.key"
umask 077
for user in root okhsunrog; do
    getent shadow "$user" | cut -d: -f2 > "$target/etc/nixos/secrets/$user-password-hash"
    [[ -s $target/etc/nixos/secrets/$user-password-hash ]]
done
export NIX_CONFIG='experimental-features = nix-command flakes'
"$installer/bin/nixos-install" --root "$target" --system "$system" \
    --no-root-passwd --no-channel-copy

# Keep a clean source copy for rebuilding, without ignored files or .git.
git -c safe.directory="$repo" -C "$repo" archive HEAD | tar -x -C "$target/etc/nixos"
chmod 0755 "$target/etc/nixos"
find "$target/etc/nixos" -mindepth 1 -maxdepth 1 -type d ! -name secrets -exec chmod 0755 {} +
[[ $(zpool get -H -o value bootfs "$pool") == "$default_before" ]]
[[ $(zfs get -H -o value normalization "$prefix/root") == none ]]
[[ $(zfs get -H -o value utf8only "$prefix/root") == off ]]
[[ -s $target/boot/vmlinuz-nixos && -s $target/boot/initramfs-nixos.img ]]
[[ $(stat -c %a "$target/boot/initramfs-nixos.img") == 600 ]]
"$repo/scripts/verify-framework.sh" "$target"
zfs snapshot -r "$prefix@fresh-install"
sync -f "$target"
echo "Installed $prefix/root; existing bootfs is unchanged. Reboot manually and select it in ZFSBootMenu."
