#!/usr/bin/env bash
# The privileged half never evaluates Nix expressions or accesses Git.
set -euo pipefail
if [[ $EUID != 0 || $# != 1 ]]; then
    echo "Usage: sudo $0 /nix/store/...-framework-module-signing.json" >&2
    echo 'Normally use scripts/rebuild-framework.sh as your regular user.' >&2
    exit 1
fi
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
exec uv run --offline --no-project --python python3 "$repo/scripts/sign-framework-modules.py" "$1"
