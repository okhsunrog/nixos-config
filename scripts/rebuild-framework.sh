#!/usr/bin/env bash
# Build/evaluate with the owner's cache and Git credentials. Elevate private
# input downloads, signing and installation; keys never enter derivations.
set -euo pipefail
if [[ $EUID == 0 ]]; then
    echo 'Run this command as your regular user, without sudo.' >&2
    exit 1
fi
action=${1:-boot}
case "$action" in
    boot|switch|build) ;;
    *) echo "Usage: $0 [boot|switch|build] [-- NIX_BUILD_OPTIONS...]" >&2; exit 1 ;;
esac
if [[ $action != build && ! -e /etc/NIXOS ]]; then
    echo 'Install boot/switch configurations from NixOS. Use build when preparing from another OS.' >&2
    exit 1
fi
if (( $# )); then shift; fi
if [[ ${1:-} == -- ]]; then shift; fi
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo"
mkdir -p .work
exec 9>.work/framework-rebuild.lock
flock -n 9 || { echo 'Another Framework rebuild is already running.' >&2; exit 1; }
"$repo/scripts/prefetch-framework-inputs.sh"
base="$repo#nixosConfigurations.framework.config"
nix build "$base.system.build.frameworkEnvironments" --out-link result-environments "$@"
uv run --offline --no-cache --no-project --no-managed-python \
    "$repo/modules/framework-environments/home.py" \
    --manifest "$(readlink -e result-environments)" preflight --action "$action"
nix build "$base.system.build.frameworkModuleSigningPlan" \
    --out-link result-module-signing "$@"
sudo "$repo/scripts/sign-framework-modules.sh" "$(readlink -e result-module-signing)"
# Update only the public input, with the normal user's ownership/credentials.
nix flake update signed-modules
# Build with the owner's cache/credentials, then sign outside derivations.
nix build "$base.system.build.frameworkEfiPlan" --out-link result-efi-plan "$@"
sudo "$repo/scripts/prepare-framework-loader.sh" "$(readlink -e result-efi-plan)"
nix build "$base.system.build.toplevel" --out-link result-framework "$@"
system=$(readlink -e result-framework)
# Recheck the exact closure and live mount after a potentially long build.
uv run --offline --no-cache --no-project --no-managed-python \
    "$repo/modules/framework-environments/home.py" \
    --manifest "$system/etc/framework-environments.json" preflight --action "$action"
if [[ $action == build ]]; then
    echo "Built $system; the installed system is unchanged."
    exit 0
fi
if [[ $action == switch ]]; then
    sudo "$system/bin/switch-to-configuration" dry-activate
fi
previous=$(readlink -e /nix/var/nix/profiles/system || true)
sudo nix-env --profile /nix/var/nix/profiles/system --set "$system"
if sudo "$system/bin/switch-to-configuration" "$action"; then
    echo "Installed $system ($action)."
else
    # Restore only the pointer we changed, never a concurrently selected system.
    if [[ -n $previous && $(readlink -e /nix/var/nix/profiles/system) == "$system" ]]; then
        sudo nix-env --profile /nix/var/nix/profiles/system --set "$previous"
    fi
    echo 'Installation failed. The previous profile was retained where possible; inspect the activation log before retrying.' >&2
    exit 1
fi
