#!@bash@
# shellcheck shell=bash disable=SC2239
set -euo pipefail
export PATH=@path@

# systemd generator arguments: normal, early, late output directories.
early=${2:?missing early generator directory}
cmdline=${ZBM_TEST_CMDLINE:-/proc/cmdline}
dataset=
read -r -a words < "$cmdline"
for word in "${words[@]}"; do
    case "$word" in
        root=ZFS=*) dataset=${word#root=ZFS=} ;;
    esac
done

# Fail closed instead of accidentally booting the root baked into the initrd.
if [[ $dataset != '@pool@/'* ]] || [[ ! $dataset =~ ^[A-Za-z0-9_./:-]+$ ]] || [[ $dataset == *..* ]]; then
    echo 'Missing or invalid ZFSBootMenu root=ZFS= dataset' >&2
    # A leading slash cannot name a ZFS dataset, so this cannot select a BE.
    dataset=/invalid-zbm-root
fi

mkdir -p "$early/initrd-root-fs.target.requires"
cat > "$early/sysroot.mount" <<EOF
[Unit]
Description=Root filesystem selected by ZFSBootMenu
DefaultDependencies=no
Requires=zfs-import-@pool@.service
After=zfs-import-@pool@.service
Before=initrd-root-fs.target
[Mount]
What=$dataset
Where=/sysroot
Type=zfs
Options=zfsutil,rw
EOF
ln -s ../sysroot.mount "$early/initrd-root-fs.target.requires/sysroot.mount"
