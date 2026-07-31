#!/usr/bin/env bash
# Stop background port-forwards started by port-forward.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
PID_FILE="$ROOT_DIR/.pf.pid"

[ -f "$PID_FILE" ] || exit 0

killed=0
while read -r pid; do
  if kill "$pid" 2>/dev/null; then
    killed=$((killed + 1))
  fi
done < "$PID_FILE"
rm -f "$PID_FILE"

[ "$killed" -gt 0 ] && printf "  Port-forwards stopped.\n" || true
