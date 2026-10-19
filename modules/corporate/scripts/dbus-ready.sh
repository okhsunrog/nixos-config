#!/bin/bash
set -euo pipefail
for ((i=0;i<100;i++)); do
  [[ -S /run/corporate-agent-dbus/system-bus ]] && exit 0
  sleep .05
done
exit 1
