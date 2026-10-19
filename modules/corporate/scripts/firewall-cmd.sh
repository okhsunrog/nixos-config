#!/bin/bash
# Compatibility for NAC's runtime --get-target query. All values come from firewalld.
set -euo pipefail
zone=
if (( $# == 3 )) && [[ $1 == --zone && $3 == --get-target ]]; then
  zone=$2
elif (( $# == 2 )) && [[ $1 == --zone=* && $2 == --get-target ]]; then
  zone=${1#--zone=}
else
  exec @FIREWALL_CMD@ "$@"
fi
[[ $zone =~ ^[[:alnum:]_-]+$ ]] || { echo 'Invalid zone name' >&2; exit 2; }
address=${DBUS_SYSTEM_BUS_ADDRESS:-unix:path=/run/dbus/system_bus_socket}
target=$(busctl --address="$address" --json=short call \
  org.fedoraproject.FirewallD1 /org/fedoraproject/FirewallD1 \
  org.fedoraproject.FirewallD1.zone getZoneSettings2 s "$zone" |
  jq -er '.data[0].target.data | select(type == "string" and length > 0)')
if [[ $target == '%%REJECT%%' ]]; then target=REJECT; fi
printf '%s\n' "$target"
