#!/usr/bin/env bash
# Deploy the Mattermost installation CR (and optional components)
# Usage: up.sh [--ha] [--monitoring]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

source "$ROOT_DIR/.env"

PROFILE="${PROFILE:-mm-repro}"
NAMESPACE="${NAMESPACE:-mattermost}"
MM_VERSION="${MM_VERSION:-10.5.0}"
MM_DOMAIN="${MM_DOMAIN:-mattermost.local}"
MINIO_BUCKET="${MINIO_BUCKET:-mattermost}"

HA=false
MONITORING=false

for arg in "$@"; do
  case "$arg" in
    --ha)         HA=true ;;
    --monitoring) MONITORING=true ;;
    --all)        HA=true; MONITORING=true ;;
  esac
done

K="kubectl --context $PROFILE"
log()  { printf "\033[34m==>\033[0m %s\n" "$*"; }
ok()   { printf "\033[32m ✓\033[0m %s\n" "$*"; }
warn() { printf "\033[33m  !\033[0m %s\n" "$*"; }

# ─── Select manifest and validate requirements ─────────────────────────────

if [ "$HA" = true ]; then
  MANIFEST="$ROOT_DIR/manifests/mattermost/installation-ha.yaml"
  # HA requires a license secret
  if ! $K -n "$NAMESPACE" get secret mattermost-license >/dev/null 2>&1; then
    echo "ERROR: HA deployment requires an Enterprise license."
    echo "  Place your license at 'license.mattermost' and run: make generate-secrets"
    exit 1
  fi
  log "Deploying HA installation (2 replicas)"
else
  MANIFEST="$ROOT_DIR/manifests/mattermost/installation.yaml"
  log "Deploying standard installation (1 replica)"
fi

# ─── Apply Mattermost CR (with variable substitution) ─────────────────────

# envsubst replaces ${MM_VERSION}, ${MM_DOMAIN}, ${MINIO_BUCKET} in the manifests
export MM_VERSION MM_DOMAIN MINIO_BUCKET

envsubst < "$MANIFEST" | $K apply -f -
ok "Mattermost CR applied"

# ─── Wait for rollout ──────────────────────────────────────────────────────

log "Waiting for Mattermost to become ready (this may take a few minutes on first run)..."
log "The operator is pulling images and running database migrations."

# Poll the Mattermost CR status instead of just the deployment
TIMEOUT=600
ELAPSED=0
while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
  MM_STATUS=$($K -n "$NAMESPACE" get mattermost mattermost \
    -o jsonpath='{.status.state}' 2>/dev/null || echo "unknown")

  if [ "$MM_STATUS" = "stable" ]; then
    ok "Mattermost is stable"
    break
  fi

  printf "\r  status: %-20s  (%ds elapsed)" "$MM_STATUS" "$ELAPSED"
  sleep 10
  ELAPSED=$((ELAPSED + 10))
done

if [ "$MM_STATUS" != "stable" ]; then
  warn "Mattermost did not reach 'stable' state within ${TIMEOUT}s"
  warn "Check logs with: make logs"
  warn "Check events with: kubectl --context $PROFILE -n $NAMESPACE describe mattermost mattermost"
fi

# ─── Optional: Monitoring ──────────────────────────────────────────────────

if [ "$MONITORING" = true ]; then
  log "Installing kube-prometheus-stack (Prometheus + Grafana)"

  helm --kube-context "$PROFILE" repo add prometheus-community \
    https://prometheus-community.github.io/helm-charts 2>/dev/null || true
  helm --kube-context "$PROFILE" repo update

  helm --kube-context "$PROFILE" upgrade --install kube-prometheus-stack \
    prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --create-namespace \
    --set grafana.adminPassword=admin \
    --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
    --wait --timeout 5m

  ok "Prometheus + Grafana installed (Grafana admin: admin / admin)"
  echo "  Access Grafana via: make port-forward  (then visit http://localhost:3000)"
fi

# ─── Port-forwards ────────────────────────────────────────────────────────

printf "\n\033[1mStarting port-forwards:\033[0m\n"
bash "$SCRIPT_DIR/port-forward.sh"

# ─── Summary ──────────────────────────────────────────────────────────────

printf "\n\033[1mMattermost is running!\033[0m\n\n"
echo "  Ingress (DNS-based): make hosts  → then https://${MM_DOMAIN}"
echo ""
echo "  Useful commands:"
echo "  • make logs         — stream pod logs"
echo "  • make status       — deployment health overview"
echo "  • make echo-logins  — print all credentials"
echo ""
