#!/bin/bash
set -euo pipefail
args=(unix:path=/run/dbus/system_bus_socket /run/corporate-agent-dbus/system-bus --filter)
for name in org.freedesktop.login1 org.freedesktop.hostname1 org.fedoraproject.FirewallD1; do
  args+=("--see=$name")
  for method in org.freedesktop.DBus.Properties.Get org.freedesktop.DBus.Properties.GetAll org.freedesktop.DBus.Introspectable.Introspect org.freedesktop.DBus.Peer.Ping org.freedesktop.DBus.Peer.GetMachineId; do
    args+=("--call=$name=$method")
  done
done
for method in ListUsers ListSessions ListSessionsEx GetUser GetSession GetSessionByPID GetUserByPID; do
  args+=("--call=org.freedesktop.login1=org.freedesktop.login1.Manager.$method@/org/freedesktop/login1")
done
args+=("--call=org.fedoraproject.FirewallD1=org.fedoraproject.FirewallD1.getDefaultZone")
for method in getZoneSettings getZoneSettings2 getZones getActiveZones getTarget; do
  args+=("--call=org.fedoraproject.FirewallD1=org.fedoraproject.FirewallD1.zone.$method")
done
exec xdg-dbus-proxy "${args[@]}"
