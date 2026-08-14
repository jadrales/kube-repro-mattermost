#!/usr/bin/env bash
# Generate a self-signed TLS certificate for the local Mattermost domain and
# sync it into the cluster as the 'mattermost-tls' k8s secret.
# Called automatically by generate-secrets.sh; also available as 'make generate-tls'.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

source "$ROOT_DIR/.env"

PROFILE="${PROFILE:-mm-repro}"
NAMESPACE="${NAMESPACE:-mattermost}"
MM_DOMAIN="${MM_DOMAIN:-mattermost.local}"

K="kubectl --context $PROFILE -n $NAMESPACE"
TLS_DIR="$ROOT_DIR/.tls"

log() { printf "\033[34m==>\033[0m %s\n" "$*"; }
ok()  { printf "\033[32m ✓\033[0m %s\n" "$*"; }

mkdir -p "$TLS_DIR"

if [ -f "$TLS_DIR/tls.crt" ] && [ -f "$TLS_DIR/tls.key" ]; then
  log "Existing TLS cert found at .tls/ — syncing to Kubernetes..."
else
  log "Generating self-signed TLS certificate for $MM_DOMAIN..."

  # Write openssl config with SAN covering both the domain and localhost
  cat > "$TLS_DIR/openssl.cnf" << EOF
[req]
distinguished_name = req_dn
x509_extensions    = v3_ca
prompt             = no

[req_dn]
CN = $MM_DOMAIN
O  = Mattermost Repro

[v3_ca]
subjectAltName   = DNS:$MM_DOMAIN,DNS:localhost,IP:127.0.0.1
keyUsage         = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
basicConstraints = CA:FALSE
EOF

  openssl req -x509 -newkey rsa:2048 -days 825 -nodes \
    -keyout "$TLS_DIR/tls.key" \
    -out    "$TLS_DIR/tls.crt" \
    -config "$TLS_DIR/openssl.cnf" 2>/dev/null

  ok "Certificate written to .tls/tls.crt"
  printf "  \033[90mTo skip the browser security warning, import .tls/tls.crt as a trusted CA.\033[0m\n"
fi

log "Creating Kubernetes TLS secret: mattermost-tls"
$K create secret tls mattermost-tls \
  --cert="$TLS_DIR/tls.crt" \
  --key="$TLS_DIR/tls.key" \
  --dry-run=client -o yaml | $K apply -f -
ok "mattermost-tls"
