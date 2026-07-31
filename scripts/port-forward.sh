#!/usr/bin/env bash
# Start port-forwards for all repro services in the background.
# PIDs are tracked in .pf.pid so 'make stop' can clean them up automatically.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
PID_FILE="$ROOT_DIR/.pf.pid"

source "$ROOT_DIR/.env"

PROFILE="${PROFILE:-mm-repro}"
NAMESPACE="${NAMESPACE:-mattermost}"

K="kubectl --context $PROFILE -n $NAMESPACE"

# Kill any previously tracked port-forwards before (re-)starting
if [ -f "$PID_FILE" ]; then
  while read -r pid; do
    kill "$pid" 2>/dev/null || true
  done < "$PID_FILE"
  rm -f "$PID_FILE"
fi

started=0

# Mattermost
if $K get svc mattermost >/dev/null 2>&1; then
  $K port-forward svc/mattermost 8065:8065 8067:8067 >/dev/null 2>&1 &
  echo $! >> "$PID_FILE"
  printf "  \033[36mMattermost\033[0m       → http://localhost:8065\n"
  started=$((started + 1))
fi

# MailHog
if $K get svc mailhog >/dev/null 2>&1; then
  $K port-forward svc/mailhog 8025:8025 >/dev/null 2>&1 &
  echo $! >> "$PID_FILE"
  printf "  \033[36mMailHog (email)\033[0m  → http://localhost:8025\n"
  started=$((started + 1))
fi

# MinIO
if $K get svc minio >/dev/null 2>&1; then
  $K port-forward svc/minio 9000:9000 9001:9001 >/dev/null 2>&1 &
  echo $! >> "$PID_FILE"
  printf "  \033[36mMinIO API\033[0m        → http://localhost:9000\n"
  printf "  \033[36mMinIO Console\033[0m    → http://localhost:9001\n"
  started=$((started + 1))
fi

# Grafana (only if monitoring stack is deployed)
if kubectl --context "$PROFILE" -n monitoring get svc kube-prometheus-stack-grafana >/dev/null 2>&1; then
  kubectl --context "$PROFILE" -n monitoring \
    port-forward svc/kube-prometheus-stack-grafana 3000:80 >/dev/null 2>&1 &
  echo $! >> "$PID_FILE"
  printf "  \033[36mGrafana\033[0m          → http://localhost:3000  (admin / admin)\n"
  started=$((started + 1))
fi

if [ "$started" -eq 0 ]; then
  printf "  \033[90mNo services found — run 'make run' first\033[0m\n"
else
  printf "\n  Port-forwards running in background. Stopped automatically by 'make stop'.\n"
fi
