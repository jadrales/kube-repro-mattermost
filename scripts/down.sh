#!/usr/bin/env bash
# Remove the Mattermost CR — leaves the cluster, PVCs, operator, and core
# infrastructure (Postgres, MinIO) intact so data survives.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

source "$ROOT_DIR/.env"

PROFILE="${PROFILE:-mm-repro}"
NAMESPACE="${NAMESPACE:-mattermost}"

K="kubectl --context $PROFILE"
log()  { printf "\033[34m==>\033[0m %s\n" "$*"; }
ok()   { printf "\033[32m ✓\033[0m %s\n" "$*"; }

log "Removing Mattermost CR"
if $K -n "$NAMESPACE" get mattermost mattermost >/dev/null 2>&1; then
  $K -n "$NAMESPACE" delete mattermost mattermost
  ok "Mattermost CR deleted"
else
  echo "  No Mattermost CR found — nothing to remove"
fi

# The operator cleans up the Deployment and Service when the CR is deleted,
# but Secrets and PVCs are intentionally left so data persists across resets.
echo ""
echo "  Postgres data:  preserved in PVC"
echo "  MinIO data:     preserved in PVC"
echo "  Secrets:        preserved"
echo ""
echo "  Run 'make run' to redeploy, or 'CONFIRM=yes make do-nuke' to delete everything"
