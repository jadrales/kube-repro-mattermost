#!/usr/bin/env bash
# Display health overview: pods, Mattermost CR, resources, and (with --logins) credentials.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

source "$ROOT_DIR/.env"

PROFILE="${PROFILE:-mm-repro}"
NAMESPACE="${NAMESPACE:-mattermost}"
MM_DOMAIN="${MM_DOMAIN:-mattermost.local}"
MINIO_ACCESS_KEY="${MINIO_ACCESS_KEY:-minioadmin}"
MINIO_SECRET_KEY="${MINIO_SECRET_KEY:-minioadmin}"

K="kubectl --context $PROFILE"
LOGINS_ONLY=false
[ "${1:-}" = "--logins" ] && LOGINS_ONLY=true

header() { printf "\n\033[1m%s\033[0m\n" "$*"; }
row()    { printf "  %-28s %s\n" "$1" "$2"; }

if [ "$LOGINS_ONLY" = false ]; then
  # ─── Cluster ──────────────────────────────────────────────────────────────
  header "Cluster"
  MINIKUBE_STATUS=$(minikube status -p "$PROFILE" --format '{{.Host}}' 2>/dev/null || echo "unknown")
  row "Minikube ($PROFILE):" "$MINIKUBE_STATUS"
  MINIKUBE_IP=$(minikube ip -p "$PROFILE" 2>/dev/null || echo "n/a")
  row "Minikube IP:" "$MINIKUBE_IP"

  # ─── Mattermost CR ────────────────────────────────────────────────────────
  header "Mattermost Installation"
  if $K -n "$NAMESPACE" get mattermost mattermost >/dev/null 2>&1; then
    MM_STATE=$($K -n "$NAMESPACE" get mattermost mattermost \
      -o jsonpath='{.status.state}' 2>/dev/null || echo "unknown")
    MM_VER=$($K -n "$NAMESPACE" get mattermost mattermost \
      -o jsonpath='{.spec.version}' 2>/dev/null || echo "unknown")
    MM_ENDPOINT=$($K -n "$NAMESPACE" get mattermost mattermost \
      -o jsonpath='{.status.endpoint}' 2>/dev/null || echo "n/a")
    row "State:" "$MM_STATE"
    row "Version:" "$MM_VER"
    row "Endpoint:" "$MM_ENDPOINT"
  else
    row "Status:" "not deployed (run 'make run')"
  fi

  # ─── Pods ─────────────────────────────────────────────────────────────────
  header "Pods — namespace: $NAMESPACE"
  $K -n "$NAMESPACE" get pods \
    -o custom-columns='NAME:.metadata.name,READY:.status.containerStatuses[0].ready,STATUS:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount,AGE:.metadata.creationTimestamp' \
    2>/dev/null || echo "  (none)"

  # ─── PVCs (data persistence) ───────────────────────────────────────────────
  header "Persistent Volumes (data storage)"
  $K -n "$NAMESPACE" get pvc 2>/dev/null || echo "  (none)"

  # ─── Resource usage ────────────────────────────────────────────────────────
  header "Resource Usage"
  $K -n "$NAMESPACE" top pods 2>/dev/null || echo "  (metrics-server not ready yet)"
fi

# ─── Logins / Credentials ─────────────────────────────────────────────────

header "Access & Credentials"
printf "\n"
printf "  \033[1mMattermost\033[0m\n"
printf "    Port-forward:   http://localhost:8065  (run: make port-forward)\n"
printf "    Ingress:        http://%s        (run: make hosts, then make tunnel)\n" "$MM_DOMAIN"
printf "    First login:    Create an account at the URL above\n"
printf "\n"
printf "  \033[1mMailHog (email capture)\033[0m\n"
printf "    URL:            http://localhost:8025  (run: make port-forward)\n"
printf "    No credentials required\n"
printf "\n"
printf "  \033[1mMinIO (filestore)\033[0m\n"
printf "    Console:        http://localhost:9001  (run: make port-forward)\n"
printf "    Access key:     %s\n" "$MINIO_ACCESS_KEY"
printf "    Secret key:     %s\n" "$MINIO_SECRET_KEY"
printf "\n"
if $K -n "$NAMESPACE" get secret mattermost-license >/dev/null 2>&1; then
  printf "  \033[32m✓ Enterprise license loaded\033[0m\n"
else
  printf "  \033[33m! No license — running Team Edition\033[0m\n"
  printf "    Place license at 'license.mattermost' → make generate-secrets → make reset\n"
fi

# LDAP credentials (shown only if LDAP is deployed)
if $K -n "$NAMESPACE" get deployment openldap >/dev/null 2>&1; then
  printf "\n  \033[1mOpenLDAP\033[0m\n"
  printf "    Server:         openldap.%s.svc.cluster.local:389\n" "$NAMESPACE"
  printf "    Bind DN:        cn=admin,dc=mattermost,dc=local\n"
  printf "    Bind password:  mmadmin\n"
  printf "    User base DN:   ou=users,dc=mattermost,dc=local\n"
  printf "    Test users:     user1–user5 / Password1\n"
  printf "    Admin user:     ldap-admin / mmadmin\n"
fi

printf "\n"
