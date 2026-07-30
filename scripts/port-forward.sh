#!/usr/bin/env bash
# Set up port-forwarding for all repro services.
# Runs all forwards in the background and prints a summary.
# Ctrl+C kills all of them.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

source "$ROOT_DIR/.env"

PROFILE="${PROFILE:-mm-repro}"
NAMESPACE="${NAMESPACE:-mattermost}"

K="kubectl --context $PROFILE -n $NAMESPACE"

cleanup() {
  printf "\n\033[33mStopping port forwards...\033[0m\n"
  kill $(jobs -p) 2>/dev/null || true
}
trap cleanup EXIT INT TERM

wait_for_pod() {
  local label="$1"
  local timeout=60
  local elapsed=0
  while ! $K get pod -l "$label" --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null | grep -q .; do
    if [ "$elapsed" -ge "$timeout" ]; then
      printf "\033[31mTimeout waiting for pod with label %s\033[0m\n" "$label"
      return 1
    fi
    printf "  waiting for %s to be running...\n" "$label"
    sleep 5
    elapsed=$((elapsed + 5))
  done
}

printf "\033[1mStarting port-forwards\033[0m\n\n"

# Mattermost
if $K get svc mattermost >/dev/null 2>&1; then
  $K port-forward svc/mattermost 8065:8065 8067:8067 &
  printf "  \033[36mMattermost\033[0m       → http://localhost:8065\n"
else
  printf "  \033[90mMattermost service not found — run 'make run' first\033[0m\n"
fi

# MailHog
if $K get svc mailhog >/dev/null 2>&1; then
  $K port-forward svc/mailhog 8025:8025 &
  printf "  \033[36mMailHog (email)\033[0m  → http://localhost:8025\n"
fi

# MinIO console
if $K get svc minio >/dev/null 2>&1; then
  $K port-forward svc/minio 9000:9000 9001:9001 &
  printf "  \033[36mMinIO API\033[0m        → http://localhost:9000\n"
  printf "  \033[36mMinIO Console\033[0m    → http://localhost:9001\n"
fi

# Grafana (if monitoring is deployed)
if kubectl --context "$PROFILE" -n monitoring get svc kube-prometheus-stack-grafana >/dev/null 2>&1; then
  kubectl --context "$PROFILE" -n monitoring \
    port-forward svc/kube-prometheus-stack-grafana 3000:80 &
  printf "  \033[36mGrafana\033[0m          → http://localhost:3000  (admin / admin)\n"
fi

printf "\n  Press \033[1mCtrl+C\033[0m to stop all forwards\n\n"

# Wait indefinitely
wait
