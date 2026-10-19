#!/usr/bin/env bash
# Bootstrap authenticated Nix downloads before the target's first activation.
set -euo pipefail
if [[ $EUID != 0 || $# -lt 3 ]]; then
    echo "Usage: sudo $0 ROOT ENCRYPTED_SECRETS NIX_SUBCOMMAND [ARGS...] (sops must be on PATH)" >&2
    exit 1
fi
root=$(realpath -- "$1")
secrets=$(realpath -- "$2")
shift 2
key=${root%/}/var/lib/sops-nix/key.txt
[[ -s $key ]]
# Only this credential must live in RAM, irrespective of TMPDIR/build caches.
[[ $(findmnt -n -o FSTYPE --target /run) == tmpfs ]]
umask 077
work=$(mktemp -d /run/nixos-forgejo.XXXXXXXX)
trap 'rm -rf -- "$work"' EXIT
SOPS_AGE_KEY_FILE="$key" sops decrypt --extract '["forgejo-netrc"]' \
    "$secrets" > "$work/.netrc"
# Preserve the normal persistent Nix/Git cache while giving Git/libcurl a
# temporary HOME containing only its protected netrc credential.
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
HOME="$work" nix --extra-experimental-features 'nix-command flakes' --option netrc-file "$work/.netrc" "$@"
