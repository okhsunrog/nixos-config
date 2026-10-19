#!/bin/bash
set -euo pipefail
[[ $EUID == 0 ]] || { echo 'Run with sudo: sudo agent-audit ...' >&2; exit 1; }
archive=/var/lib/corporate-agent-archive
# ausearch 4.2.1 drops whole events with some leading AppArmor AVC records.
# Normalize only the display stream; retain every original record on disk.
audit_records() {
  local files=() file
  shopt -s nullglob
  files=(/var/log/audit/audit.log.[0-9]*)
  if (( ${#files[@]} )); then
    while IFS= read -r file; do cat -- "$file"; done < <(printf '%s\n' "${files[@]}" | sort -Vr)
  fi
  cat /var/log/audit/audit.log
}
audit_view() {
  audit_records | sed '/^type=AVC /d' | ausearch -if /dev/stdin "$@"
}
case "${1:-list}" in
  list)
    printf 'Capture ID | UTC time | PID | SHA256 | Source\n'
    while IFS= read -r -d '' file; do
      id=$(basename "$(dirname "$file")")
      jq -r --arg id "$id" '[$id, .captured_at, (.pid|tostring), .sha256, .source] | @tsv' "$file"
    done < <(find "$archive" -mindepth 2 -maxdepth 2 -name metadata.json -type f -print0 | sort -z)
    ;;
  show)
    id=${2:?Usage: sudo agent-audit show CAPTURE_ID}
    [[ $id =~ ^[0-9TZ.-]+-[0-9]+$ ]] || { echo 'Invalid capture ID' >&2; exit 1; }
    [[ -d $archive/$id && ! -L $archive/$id ]] || exit 1
    cat "$archive/$id/metadata.json"
    printf '\n--- Script (control characters escaped) ---\n'
    cat -v "$archive/$id/script"
    printf '\n'
    ;;
  commands)
    # --ppid selects immediate children, not an entire recursive process tree.
    if [[ ${2:-} ]]; then
      [[ $2 =~ ^[0-9]+$ ]] || exit 1
      audit_view -k corp_exec --ppid "$2" -i
    else
      audit_view -k corp_exec -i
    fi
    ;;
  forks) audit_view -k corp_fork -i ;;
  apparmor)
    audit_records | awk '/^type=AVC / && /profile="corporate-(orbit|nac)"/'
    ;;
  status)
    systemctl --no-pager --full status agent-script-archive.service
    auditctl -s
    printf '\nActive LSMs: '; cat /sys/kernel/security/lsm; printf '\n'
    ;;
  *) echo 'Usage: sudo agent-audit {list|show ID|commands [PARENT_PID]|forks|apparmor|status}' >&2; exit 2 ;;
esac
