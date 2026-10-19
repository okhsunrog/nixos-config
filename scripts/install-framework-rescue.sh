#!/usr/bin/env bash
set -euo pipefail
if [[ $EUID != 0 || $# != 1 ]]; then
    echo "Usage: sudo $0 /nix/store/...-framework-rescue-plan.json" >&2
    exit 1
fi
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
exec uv run --offline --no-project --python python3 "$repo/scripts/install-framework-rescue.py" "$1"
