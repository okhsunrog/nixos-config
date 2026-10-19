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
[[ $(findmnt -n -o SOURCE --target "$target/home") == novafs/nixos0/data/home ]]
system=$(readlink -e "$repo/result-framework")
bundle="$target/boot/zbm-rs/nixos/$(basename "$system")"
[[ -s $bundle/kernel && -s $bundle/initrd && -s $bundle/prepared.json ]]
[[ $(stat -Lc %a "$bundle/initrd") == 600 ]]
source_hash=$(sha256sum "$target$system/boot.json")
[[ $(jq -r .bootspec_sha256 "$bundle/prepared.json") == "${source_hash%% *}" ]]
sbverify --cert "$target/var/lib/secureboot/db.pem" "$bundle/kernel"
kh=$(sha256sum "$bundle/kernel"); kh=${kh%% *}
ih=$(sha256sum "$bundle/initrd"); ih=${ih%% *}
found=0
while IFS= read -r -d '' payload; do
    if jq -e --arg kh "$kh" --arg ih "$ih" '.kernel.sha256 == $kh and .initramfs.sha256 == $ih' "$payload" >/dev/null; then
        openssl cms -verify -binary -inform DER -noverify -nointern \
            -certfile "$target/var/lib/secureboot/db.pem" -in "${payload%.json}.cms" \
            -content "$payload" -out /dev/null
        found=1
    fi
done < <(find "$target/boot/zbm-rs/authorizations" -type f -name '*.json' -print0)
((found == 1))
[[ -s $target/etc/zfs/zroot.key && $(stat -c %a "$target/etc/zfs/zroot.key") == 0 ]]
[[ -s $target/var/lib/sops-nix/key.txt ]]
[[ $(stat -c %a "$target/var/lib/sops-nix/key.txt") == 0 ]]
[[ $(stat -c %u "$target/var/lib/sops-nix/key.txt") == 0 ]]
awk '$1 == "novafs/nixos0/data/home" && $2 == "/home" && $3 == "zfs" && $4 ~ /(^|,)x-initrd.mount(,|$)/ { found = 1 } END { exit !found }' "$system/etc/fstab"
[[ $(chroot "$target" "$system/sw/bin/od" -An -tx1 /etc/hostid | tr -d ' \n') == 0cb1ba00 ]]
echo "Verified $dataset: layout, source-bound prepared generation, kernel signature, CMS and boot hashes. Physical boot/TPM remain to be tested."
