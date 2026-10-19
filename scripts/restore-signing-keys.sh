#!/usr/bin/env bash
# Explicit, idempotent recovery. Never replace a different existing key.
set -euo pipefail
if [[ $EUID != 0 || $# != 2 ]]; then
    echo "Usage: sudo $0 ROOT ENCRYPTED_SECRETS (sops and jq must be on PATH)" >&2
    exit 1
fi
root=$(realpath -- "$1")
secrets=$(realpath -- "$2")
key=${root%/}/var/lib/sops-nix/key.txt
[[ -s $key ]]
[[ $(findmnt -n -o FSTYPE --target /run) == tmpfs ]]
umask 077
work=$(mktemp -d /run/nixos-signing-recovery.XXXXXXXX)
trap 'rm -rf -- "$work"' EXIT
SOPS_AGE_KEY_FILE="$key" sops decrypt --extract '["recovery"]' "$secrets" > "$work/recovery.json"
restore() {
    local field=$1 relative=$2 mode=$3 destination
    destination=${root%/}/$relative
    jq -erj --arg field "$field" '.[$field]' "$work/recovery.json" > "$work/value"
    if [[ -e $destination || -L $destination ]]; then
        if ! cmp -s "$work/value" "$destination"; then
            echo "Refusing to replace a different existing file: $destination" >&2
            exit 1
        fi
        echo "Unchanged: $destination"
        return
    fi
    install -d -m700 "$(dirname -- "$destination")"
    install -m "$mode" "$work/value" "$destination"
    echo "Restored: $destination"
}
restore secureboot-db-key var/lib/secureboot/db.key 0600
restore secureboot-db-certificate var/lib/secureboot/db.pem 0644
restore secureboot-ima-key var/lib/secureboot/ima.key 0600
restore secureboot-ima-certificate var/lib/secureboot/ima.pem 0644
restore secureboot-pcr-key var/lib/secureboot/pcr.key 0600
restore secureboot-pcr-public-key var/lib/secureboot/pcr-public.pem 0644
restore secureboot-PK-key var/lib/sbctl/keys/PK/PK.key 0400
restore secureboot-PK-certificate var/lib/sbctl/keys/PK/PK.pem 0644
restore secureboot-KEK-key var/lib/sbctl/keys/KEK/KEK.key 0400
restore secureboot-KEK-certificate var/lib/sbctl/keys/KEK/KEK.pem 0644
restore secureboot-db-key var/lib/sbctl/keys/db/db.key 0400
restore secureboot-db-certificate var/lib/sbctl/keys/db/db.pem 0644
restore sbctl-owner-guid var/lib/sbctl/GUID 0600
