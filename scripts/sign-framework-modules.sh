#!/usr/bin/env bash
# Refresh the externally signed public input before changing the kernel ABI.
set -euo pipefail
[[ $EUID == 0 ]] || { echo 'Run with sudo; signing keys stay outside Nix.' >&2; exit 1; }
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo"
export NIX_CONFIG='experimental-features = nix-command flakes'
state=/var/lib/secureboot
if [[ ! -f $state/db.key ]]; then state=/var/lib/sbctl/keys/db; fi
[[ -s $state/db.key && -s $state/db.pem ]]
work_root=/var/lib/zbm-rs-signing
install -d -m700 "$work_root"
exec 9>"$work_root/.lock"
flock 9
[[ -d /var/lib/zbm-rs-public/framework-modules && ! -L /var/lib/zbm-rs-public/framework-modules ]] || {
    echo 'Expected the provisioned public module-input directory; inspect the bootstrap first.' >&2
    exit 1
}
work=$(mktemp -d "$work_root/modules.XXXXXXXX")
export TMPDIR="$work"
base=.#nixosConfigurations.framework.config
nix build "$base.system.build.unsignedFrameworkModules" --out-link "$work/unsigned"
nix build "$base.boot.kernelPackages.kernel.dev" --out-link "$work/kernel-dev"
kernel=$(nix eval --raw "$base.boot.kernelPackages.kernel.outPath")
version=$(nix eval --raw "$base.boot.kernelPackages.kernel.modDirVersion")
source=$(nix eval --raw --impure --expr "(builtins.getFlake (toString ./.)).inputs.zbm-rs.outPath")
uv run --offline --no-project --python python3 "$source/nix/sign-module-tree.py" \
    "$work/unsigned" "$work/signed" --kernel "$kernel" \
    --key "$state/db.key" --cert "$state/db.pem" \
    --sign-file "$work/kernel-dev/lib/modules/$version/build/scripts/sign-file"
signed=$(nix-store --add "$work/signed")
install -d -m755 /var/lib/zbm-rs-public
install -d -m700 "$work_root/roots"
nix-store --add-root "$work_root/roots/$(basename "$signed")" --realise "$signed" >/dev/null
next=/var/lib/zbm-rs-public/.framework-modules.$BASHPID
mkdir "$next"
cp -a "$signed/." "$next/"
previous=/var/lib/zbm-rs-public/framework-modules.previous.$BASHPID
mv /var/lib/zbm-rs-public/framework-modules "$previous"
if ! mv "$next" /var/lib/zbm-rs-public/framework-modules; then
    mv "$previous" /var/lib/zbm-rs-public/framework-modules
    exit 1
fi
if ! nix flake update signed-modules; then
    mv /var/lib/zbm-rs-public/framework-modules "$next"
    mv "$previous" /var/lib/zbm-rs-public/framework-modules
    exit 1
fi
echo "Signed module input updated for $version. Now run nixos-rebuild boot."
echo "Signing artifacts retained in $work"
