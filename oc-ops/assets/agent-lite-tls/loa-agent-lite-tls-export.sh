#!/usr/bin/env bash
set -euo pipefail

state_dir="${STATE_DIRECTORY:-/var/lib/loa-agent-lite-tls-export}"
logs_dir="${LOGS_DIRECTORY:-/var/log/loa-agent-lite}"
cursor_file="$state_dir/journal.cursor"
output_file="$logs_dir/application.jsonl"
poll_interval_seconds="${POLL_INTERVAL_SECONDS:-2}"

units=(
  "loa-agent-worker.service"
  "loa-agent-gateway.service"
  "loa-agent-gateway-b.service"
)

matches=()
for unit in "${units[@]}"; do
  if systemctl cat "$unit" >/dev/null 2>&1; then
    matches+=("_SYSTEMD_UNIT=$unit")
  fi
done

if [[ "${#matches[@]}" -eq 0 ]]; then
  echo "No Agent Lite systemd units were found." >&2
  exit 1
fi

mkdir -p "$state_dir" "$logs_dir"

journal_args=(
  --quiet
  --no-pager
  --output=json
  --output-fields=__REALTIME_TIMESTAMP,_HOSTNAME,_SYSTEMD_UNIT,SYSLOG_IDENTIFIER,_PID,PRIORITY,MESSAGE
  --cursor-file="$cursor_file"
)

if [[ ! -s "$cursor_file" ]]; then
  seed_output="$(journalctl --quiet --show-cursor --lines=1 2>/dev/null || true)"
  seed_cursor="$(sed -n 's/^-- cursor: //p' <<<"$seed_output" | tail -n 1)"
  if [[ -n "$seed_cursor" ]]; then
    printf '%s\n' "$seed_cursor" >"$cursor_file"
  else
    journal_args+=(--since=now)
  fi
fi

while true; do
  journalctl "${journal_args[@]}" "${matches[@]}" >>"$output_file"
  sleep "$poll_interval_seconds"
done
