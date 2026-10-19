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
age_key=${SOPS_AGE_KEY_FILE:-/var/lib/sops-nix/key.txt}
[[ -s $age_key ]]
vault=${NIXOS_SECRETS_DIR:-$(dirname -- "$repo")/nixos-secrets}
[[ -d $vault/.git && -s $vault/framework.enc.json ]]
for file in /var/lib/sbctl/keys/db/db.key /var/lib/sbctl/keys/db/db.pem \
            /var/lib/zbm-secureboot/ima/ima.key /var/lib/zbm-secureboot/ima/ima.pem \
            /etc/systemd/tpm2-pcr-signature.json /etc/systemd/tpm2-pcr-public-key.pem; do
    [[ -s $file ]]
done
[[ -d /var/lib/zbm-rs-public/framework-modules ]]
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
    -o compression=zstd "$prefix"
zfs create -u -o mountpoint=/ -o canmount=noauto "$prefix/root"
zfs create -u -o mountpoint=none "$prefix/data"
zfs create -u -o mountpoint=/home -o canmount=noauto "$prefix/data/home"
mkdir -p "$target"
mount -i -t zfs -o zfsutil "$prefix/root" "$target"
cleanup() {
    # Only our new BE's mounts. Never export the running host pool.
    if mountpoint -q "$target/home"; then umount "$target/home"; fi
    if mountpoint -q "$target"; then umount "$target"; fi
}
trap cleanup EXIT
mkdir "$target/home"
mount -i -t zfs -o zfsutil "$prefix/data/home" "$target/home"
install -d -m 0700 "$target/etc/zfs" "$target/var/lib/sops-nix"
install -d -m 0755 "$target/etc/nixos"
install -m 0000 "$age_key" "$target/var/lib/sops-nix/key.txt"
install -m 000 /etc/zfs/zroot.key "$target/etc/zfs/zroot.key"
install -d -m 0700 "$target/var/lib/secureboot"
install -m 0600 /var/lib/sbctl/keys/db/db.key "$target/var/lib/secureboot/db.key"
install -m 0600 /var/lib/zbm-secureboot/ima/ima.key "$target/var/lib/secureboot/ima.key"
install -m 0644 /var/lib/sbctl/keys/db/db.pem "$target/var/lib/secureboot/db.pem"
install -m 0644 /var/lib/zbm-secureboot/ima/ima.pem "$target/var/lib/secureboot/ima.pem"
install -d "$target/etc/systemd" "$target/var/lib/zbm-rs-public"
install -m 0644 /etc/systemd/tpm2-pcr-signature.json "$target/etc/systemd/tpm2-pcr-signature.json"
install -m 0644 /etc/systemd/tpm2-pcr-public-key.pem "$target/etc/systemd/tpm2-pcr-public-key.pem"
cp -aL /var/lib/zbm-rs-public/framework-modules "$target/var/lib/zbm-rs-public/"
export NIX_CONFIG='experimental-features = nix-command flakes'
"$installer/bin/nixos-install" --root "$target" --system "$system" \
    --no-root-passwd --no-channel-copy

# Work as the normal user after boot; /etc/nixos is only an alias.
code=$target/home/okhsunrog/code
install -d -m0755 -o1000 -g1000 "$code"
rsync -a --chown=1000:1000 --exclude='/result*' --exclude='/.work' \
    --exclude='/secrets' "$repo/" "$code/nixos-config/"
rsync -a --chown=1000:1000 "$vault/" "$code/nixos-secrets/"
rmdir "$target/etc/nixos"
ln -s /home/okhsunrog/code/nixos-config "$target/etc/nixos"
[[ $(zpool get -H -o value bootfs "$pool") == "$default_before" ]]
[[ $(zfs get -H -o value normalization "$prefix/root") == none ]]
[[ $(zfs get -H -o value utf8only "$prefix/root") == off ]]
bundle="$target/boot/zbm-rs/nixos/$(basename "$system")"
[[ -s $bundle/kernel && -s $bundle/initrd && -s $bundle/prepared.json ]]
[[ $(stat -Lc %a "$bundle/initrd") == 600 ]]
"$repo/scripts/verify-framework.sh" "$target"
zfs snapshot -r "$prefix@fresh-install"
sync -f "$target"
echo "Installed $prefix/root; existing bootfs is unchanged. Reboot manually and select it in zbm-rs."
