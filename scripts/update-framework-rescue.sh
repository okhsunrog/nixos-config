#!/usr/bin/env bash
# Deliberate rescue update, independent of the normal system/loader rebuild.
set -euo pipefail
if [[ $EUID == 0 ]]; then
    echo 'Run as the regular repository owner, without sudo.' >&2
    exit 1
fi
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo"
mkdir -p .work
exec 9>.work/framework-rebuild.lock
flock -n 9 || { echo 'Another Framework rebuild is already running.' >&2; exit 1; }
nix build .#nixosConfigurations.framework.config.system.build.frameworkRescuePlan \
    --out-link result-rescue-plan "$@"
sudo "$repo/scripts/install-framework-rescue.sh" "$(readlink -e result-rescue-plan)"
