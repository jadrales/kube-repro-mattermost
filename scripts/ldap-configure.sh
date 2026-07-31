#!/usr/bin/env bash
# Configure all Mattermost LDAP settings to point at the local OpenLDAP server,
# then trigger a sync. Runs via mmctl --local inside the Mattermost pod so no
# System Console interaction is required.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

source "$ROOT_DIR/.env"

PROFILE="${PROFILE:-mm-repro}"
NAMESPACE="${NAMESPACE:-mattermost}"

ME="kubectl --context $PROFILE -n $NAMESPACE exec deploy/mattermost --"

log() { printf "\033[34m==>\033[0m %s\n" "$*"; }
ok()  { printf "\033[32m ✓\033[0m %s\n" "$*"; }

log "Applying LDAP settings to Mattermost..."

# Connection
$ME mmctl --local config set LdapSettings.Enable true
$ME mmctl --local config set LdapSettings.LdapServer "openldap.${NAMESPACE}.svc.cluster.local"
$ME mmctl --local config set LdapSettings.LdapPort 389
$ME mmctl --local config set LdapSettings.ConnectionSecurity ""
$ME mmctl --local config set LdapSettings.BaseDN "dc=planetexpress,dc=com"
$ME mmctl --local config set LdapSettings.BindUsername "cn=admin,dc=planetexpress,dc=com"
$ME mmctl --local config set LdapSettings.BindPassword "GoodNewsEveryone"

# User sync
$ME mmctl --local config set LdapSettings.EnableSync true
$ME mmctl --local config set LdapSettings.SyncIntervalMinutes 60
$ME mmctl --local config set LdapSettings.UserFilter "(objectClass=Person)"
$ME mmctl --local config set LdapSettings.UsernameAttribute uid
$ME mmctl --local config set LdapSettings.IdAttribute uid
$ME mmctl --local config set LdapSettings.LoginIdAttribute uid
$ME mmctl --local config set LdapSettings.EmailAttribute mail
$ME mmctl --local config set LdapSettings.FirstNameAttribute givenName
$ME mmctl --local config set LdapSettings.LastNameAttribute sn
$ME mmctl --local config set LdapSettings.PictureAttribute jpegPhoto

# Group sync
$ME mmctl --local config set LdapSettings.GroupFilter "(objectClass=Group)"
$ME mmctl --local config set LdapSettings.GroupDisplayNameAttribute cn
$ME mmctl --local config set LdapSettings.GroupIdAttribute cn

# Admin filter — admin_staff members get Mattermost System Admin role
$ME mmctl --local config set LdapSettings.EnableAdminFilter true
$ME mmctl --local config set LdapSettings.AdminFilter \
  "(memberof=cn=admin_staff,ou=people,dc=planetexpress,dc=com)"

ok "LDAP settings applied."

log "Triggering initial LDAP sync..."
$ME mmctl --local ldap sync
ok "LDAP sync complete. Users and groups are now available in Mattermost."
