#!/usr/bin/env bash
# One-time environment bootstrap: minikube + Mattermost Operator
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

source "$ROOT_DIR/.env"

PROFILE="${PROFILE:-mm-repro}"
NAMESPACE="${NAMESPACE:-mattermost}"
MINIKUBE_CPUS="${MINIKUBE_CPUS:-4}"
MINIKUBE_MEMORY="${MINIKUBE_MEMORY:-8192}"
MINIKUBE_DISK="${MINIKUBE_DISK:-40g}"
MINIKUBE_DRIVER="${MINIKUBE_DRIVER:-docker}"

log()  { printf "\033[34m==>\033[0m %s\n" "$*"; }
ok()   { printf "\033[32m ✓\033[0m %s\n" "$*"; }
warn() { printf "\033[33m  !\033[0m %s\n" "$*"; }

# ─── Prerequisites ─────────────────────────────────────────────────────────

for cmd in minikube kubectl helm; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "ERROR: '$cmd' not found in PATH"
    echo "  minikube: https://minikube.sigs.k8s.io/docs/start/"
    echo "  helm:     https://helm.sh/docs/intro/install/"
    exit 1
  }
done

# ─── Minikube ──────────────────────────────────────────────────────────────

if minikube status -p "$PROFILE" --format '{{.Host}}' 2>/dev/null | grep -q "Running"; then
  ok "Minikube profile '$PROFILE' already running"
else
  log "Starting minikube profile: $PROFILE"
  minikube start \
    -p "$PROFILE" \
    --cpus="$MINIKUBE_CPUS" \
    --memory="$MINIKUBE_MEMORY" \
    --disk-size="$MINIKUBE_DISK" \
    --driver="$MINIKUBE_DRIVER"
  ok "Minikube started"
fi

# ─── Addons ────────────────────────────────────────────────────────────────

log "Enabling minikube addons"
minikube addons enable ingress         -p "$PROFILE"
minikube addons enable ingress-dns     -p "$PROFILE" 2>/dev/null || warn "ingress-dns not available (driver limitation — use 'make port-forward' instead)"
minikube addons enable metrics-server  -p "$PROFILE"
ok "Addons enabled"

# ─── Helm repos ────────────────────────────────────────────────────────────

log "Adding Mattermost Helm repository"
helm repo add mattermost https://helm.mattermost.com 2>/dev/null || true
helm repo update
ok "Helm repos updated"

# ─── Mattermost Operator ───────────────────────────────────────────────────

log "Installing Mattermost Operator"
kubectl --context "$PROFILE" create namespace mattermost-operator \
  --dry-run=client -o yaml | kubectl --context "$PROFILE" apply -f -

helm --kube-context "$PROFILE" upgrade --install mattermost-operator \
  mattermost/mattermost-operator \
  --namespace mattermost-operator \
  --values "$ROOT_DIR/config/operator-values.yaml" \
  --wait --timeout 3m

ok "Mattermost Operator installed"

# ─── Namespace + Core Infrastructure ──────────────────────────────────────

log "Creating namespace and deploying core infrastructure (Postgres, MinIO, MailHog)"
kubectl --context "$PROFILE" apply -f "$ROOT_DIR/manifests/core/namespace.yaml"

# Secrets must exist before dependent pods can schedule
bash "$SCRIPT_DIR/generate-secrets.sh"

kubectl --context "$PROFILE" apply -f "$ROOT_DIR/manifests/core/postgres.yaml"
kubectl --context "$PROFILE" apply -f "$ROOT_DIR/manifests/core/minio.yaml"
kubectl --context "$PROFILE" apply -f "$ROOT_DIR/manifests/core/mailhog.yaml"

log "Waiting for Postgres and MinIO to become ready (up to 3 minutes)..."
kubectl --context "$PROFILE" -n "$NAMESPACE" rollout status statefulset/postgres --timeout=3m
kubectl --context "$PROFILE" -n "$NAMESPACE" rollout status statefulset/minio    --timeout=3m
ok "Core infrastructure ready"

# ─── Done ──────────────────────────────────────────────────────────────────

printf "\n\033[1mSetup complete!\033[0m\n\n"
echo "  Next steps:"
echo "  1. Run 'make run' to deploy Mattermost (port-forwards start automatically)"
echo ""
echo "  Optional:"
echo "  - Place a license at 'license.mattermost' for Enterprise features"
echo "  - Run 'make run-ha' for an HA deployment (requires license)"
echo "  - Run 'make run-ldap' to add OpenLDAP test users"
echo ""
