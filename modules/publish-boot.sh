#!@bash@
# shellcheck shell=bash disable=SC2239
set -euo pipefail
export PATH=@path@
system=${1:?expected system toplevel}
system=$(readlink -f "$system")
mkdir -p /boot

# Inside nixos-enter, mountinfo retains the installer's /mnt prefix. Identify
# the filesystem by its device number instead of resolving an external path.
device=$(stat -c '%Hd:%Ld' /boot)
[[ $device == "$(stat -c '%Hd:%Ld' /)" ]]
dataset=$(findmnt -rn -t zfs -o MAJ:MIN,SOURCE | awk -v device="$device" '$1 == device { print $2; exit }')
pool=@pool@
if [[ $dataset != "$pool/"* ]] || [[ $(zfs get -H -o value mountpoint "$dataset") != / ]]; then
    echo "Refusing to publish boot files on $dataset (expected a BE in $pool)" >&2
    exit 1
fi

mkdir -p /boot/nixos-generations
exec 9>/boot/.nixos-publish.lock
flock 9
for name in vmlinuz-nixos initramfs-nixos.img nixos-current; do
    if [[ -e /boot/$name && ! -L /boot/$name ]]; then
        echo "Refusing to replace foreign /boot/$name" >&2
        exit 1
    fi
done
stage=$(mktemp -d /boot/nixos-generations/.staging.XXXXXXXX)
pointer=/boot/.nixos-current.$BASHPID
trap 'rm -rf -- "$stage"; rm -f -- "$pointer"' EXIT

cp --dereference "$system/kernel" "$stage/kernel"
cp --dereference "$system/initrd" "$stage/initrd"
chmod 0600 "$stage/initrd"
ln -s "$system" "$stage/system"
if secrets=$(jq -r '."org.nixos.bootspec.v1".initrdSecrets // empty' "$system/boot.json") && [[ -n $secrets ]]; then
    "$secrets" "$stage/initrd"
fi

# Use bootspec's parameters, but let ZBM supply the selected root and init.
# NixOS validates that spaces in individual parameters are already quoted.
params=$(jq -er '."org.nixos.bootspec.v1".kernelParams | map(select(startswith("root=") or startswith("init=") | not)) | join(" ")' "$system/boot.json")
cmdline="spl.spl_hostid=0x@hostId@ init=/boot/nixos-current/system/init rw $params"

# Properties do not hold the generation-dependent init path: the snapshot does.
zfs set org.zfsbootmenu:rootprefix=root=ZFS= "$dataset"
zfs set "org.zfsbootmenu:commandline=$cmdline" "$dataset"
zfs set "org.zfsbootmenu:keysource=$dataset" "$dataset"

# One discoverable pair, with all three paths switched by one atomic symlink.
for entry in 'vmlinuz-nixos:kernel' 'initramfs-nixos.img:initrd'; do
    name=${entry%%:*}
    file=${entry#*:}
    ln -sfn "nixos-current/$file" "/boot/$name"
done
bundle="$(basename "$system").$(basename "$stage")"
mv "$stage" "/boot/nixos-generations/$bundle"
ln -s "nixos-generations/$bundle" "$pointer"
sync -f /boot
mv -Tf "$pointer" /boot/nixos-current
mkdir -p /nix/var/nix/gcroots
ln -sfn /boot/nixos-current/system /nix/var/nix/gcroots/zfsbootmenu-current
sync -f /boot
trap - EXIT
echo "Published NixOS boot bundle for $dataset"
