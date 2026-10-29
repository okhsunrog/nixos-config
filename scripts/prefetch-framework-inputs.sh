#!/usr/bin/env bash
# Retain the exact private file input before unprivileged flake evaluation.
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
locked=$(jq -ce '
    . as $lock |
    .nodes[.root].inputs["floppa-deployment"] as $node |
    $lock.nodes[$node].locked |
    select(.type == "file" and (.url | type == "string") and (.narHash | type == "string"))
' "$repo/flake.lock")
url=$(jq -r '.url' <<< "$locked")
hash=$(jq -r '.narHash' <<< "$locked")
# File inputs use the recursive NAR hash with the fixed store name "source".
expected=$(nix-store --print-fixed-path --recursive sha256 "$hash" source)
if ! nix-store --check-validity "$expected" 2>/dev/null; then
    printf 'Fetching the pinned private Floppa deployment with root credentials.\n' >&2
    separator='?'
    [[ $url != *\?* ]] || separator='&'
    reference="file+${url}${separator}narHash=$(jq -rn --arg hash "$hash" '$hash | @uri')"
    fetched=$(sudo nix flake prefetch --json "$reference")
    # Check both values before making the input available to the rebuild.
    jq -e --arg hash "$hash" --arg path "$expected" \
        '.hash == $hash and .storePath == $path' <<< "$fetched" >/dev/null
fi
# This root also protects build-only runs and the interval before installation.
mkdir -p "$repo/.work"
nix-store --realise "$expected" --add-root "$repo/.work/floppa-deployment" >/dev/null
