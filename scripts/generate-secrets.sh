#!/usr/bin/env bash
# Create (or update) all Kubernetes secrets from .env values.
# Uses --dry-run=client | apply so it's safely idempotent.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

source "$ROOT_DIR/.env"

PROFILE="${PROFILE:-mm-repro}"
NAMESPACE="${NAMESPACE:-mattermost}"

DB_USER="${DB_USER:-mmuser}"
DB_PASSWORD="${DB_PASSWORD:-mmuser_password}"
DB_NAME="${DB_NAME:-mattermost}"
MINIO_ACCESS_KEY="${MINIO_ACCESS_KEY:-minioadmin}"
MINIO_SECRET_KEY="${MINIO_SECRET_KEY:-minioadmin}"
LICENSE_PATH="${LICENSE_PATH:-license.mattermost}"

K="kubectl --context $PROFILE -n $NAMESPACE"

log() { printf "\033[34m==>\033[0m %s\n" "$*"; }
ok()  { printf "\033[32m ✓\033[0m %s\n" "$*"; }

# ─── DB credentials secret (raw values, used by Postgres StatefulSet) ──────

log "Creating secret: mattermost-db-credentials"
$K create secret generic mattermost-db-credentials \
  --from-literal=DB_USER="$DB_USER" \
  --from-literal=DB_PASSWORD="$DB_PASSWORD" \
  --from-literal=DB_NAME="$DB_NAME" \
  --dry-run=client -o yaml | $K apply -f -
ok "mattermost-db-credentials"

# ─── DB connection secret (DSN format, used by Mattermost Operator CR) ─────

DB_DSN="postgres://${DB_USER}:${DB_PASSWORD}@postgres.${NAMESPACE}.svc.cluster.local:5432/${DB_NAME}?connect_timeout=10&sslmode=disable"

log "Creating secret: mattermost-db-secret"
$K create secret generic mattermost-db-secret \
  --from-literal=DB_CONNECTION_STRING="$DB_DSN" \
  --from-literal=DB_CONNECTION_CHECK_URL="$DB_DSN" \
  --dry-run=client -o yaml | $K apply -f -
ok "mattermost-db-secret"

# ─── Filestore secret (MinIO / S3-compatible) ───────────────────────────────

log "Creating secret: mattermost-filestore-secret"
$K create secret generic mattermost-filestore-secret \
  --from-literal=accesskey="$MINIO_ACCESS_KEY" \
  --from-literal=secretkey="$MINIO_SECRET_KEY" \
  --dry-run=client -o yaml | $K apply -f -
ok "mattermost-filestore-secret"

# ─── License secret (Enterprise only — optional) ───────────────────────────

if [ -f "$ROOT_DIR/$LICENSE_PATH" ]; then
  log "Creating secret: mattermost-license (from $LICENSE_PATH)"
  $K create secret generic mattermost-license \
    --from-file=license="$ROOT_DIR/$LICENSE_PATH" \
    --dry-run=client -o yaml | $K apply -f -
  ok "mattermost-license"
else
  printf "\033[33m  !\033[0m No license file at '%s' — deploying Team Edition\n" "$LICENSE_PATH"
  printf "    Place your license at '%s' and re-run 'make generate-secrets'\n" "$LICENSE_PATH"
fi
