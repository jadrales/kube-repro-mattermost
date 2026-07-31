# Mattermost Kubernetes Reproduction Environment
# Modeled after CS-Repro-Mattermost — for Kubernetes-based deployments via the Mattermost Operator
# Requires: minikube, kubectl, helm, GNU make, bash (WSL2 or Git Bash on Windows)

-include .env
export

PROFILE         ?= mm-repro
NAMESPACE       ?= mattermost
MM_VERSION      ?= 10.5.0
MM_DOMAIN       ?= mattermost.local
MM_REPLICAS     ?= 1
MINIKUBE_CPUS   ?= 4
MINIKUBE_MEMORY ?= 8192
MINIKUBE_DISK   ?= 40g
MINIKUBE_DRIVER ?= docker

# Always target the repro cluster, not whatever is currently active
KUBECTL := kubectl --context $(PROFILE)
HELM    := helm --kube-context $(PROFILE)

.DEFAULT_GOAL := help

.PHONY: help setup generate-secrets \
        run run-ha run-ldap run-monitoring run-all \
        start stop down reset \
        logs status port-forward port-forward-stop tunnel hosts shell \
        upgrade echo-logins do-nuke .env-check

# ─── HELP ────────────────────────────────────────────────────────────────────

help: ## Show available commands
	@printf "\n\033[1mMattermost Kubernetes Repro — $(PROFILE)\033[0m\n\n"
	@printf "  \033[90mMattermost v$(MM_VERSION)  |  namespace: $(NAMESPACE)  |  domain: $(MM_DOMAIN)\033[0m\n\n"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'
	@printf "\n"

# ─── SETUP ───────────────────────────────────────────────────────────────────

setup: .env-check ## (First run) Start minikube, enable addons, install Mattermost Operator
	@bash scripts/setup.sh

generate-secrets: .env-check ## Re-create Kubernetes secrets from current .env values
	@bash scripts/generate-secrets.sh

# ─── DEPLOY ──────────────────────────────────────────────────────────────────

run: .env-check generate-secrets ## Deploy core stack: Mattermost + Postgres + MinIO + MailHog
	@bash scripts/up.sh

run-ha: .env-check generate-secrets ## Deploy HA variant: 2 Mattermost replicas with clustering
	@bash scripts/up.sh --ha

run-ldap: .env-check ## Add OpenLDAP to a running deployment
	$(KUBECTL) apply -n $(NAMESPACE) -f manifests/optional/ldap.yaml
	@echo "LDAP deployed. Configure Mattermost at System Console > AD/LDAP"
	@echo "  LDAP server:  openldap.$(NAMESPACE).svc.cluster.local"
	@echo "  Bind DN:      cn=admin,dc=mattermost,dc=local"
	@echo "  Bind password: mmadmin"
	@echo "  User base DN: ou=users,dc=mattermost,dc=local"

run-monitoring: .env-check ## Add Prometheus + Grafana via kube-prometheus-stack
	@bash scripts/up.sh --monitoring

run-all: run run-ldap run-monitoring ## Deploy the full stack (all optional components)

# ─── LIFECYCLE ───────────────────────────────────────────────────────────────

start: ## Resume a stopped cluster — all PVC data is preserved, port-forwards restart automatically
	minikube start -p $(PROFILE)
	@echo "Waiting for pods to be ready..."
	@$(KUBECTL) -n $(NAMESPACE) wait pod -l app=mattermost \
	  --for=condition=Ready --timeout=120s 2>/dev/null || true
	@printf "\n\033[1mPort-forwards:\033[0m\n"
	@bash scripts/port-forward.sh
	@echo ""
	@echo "Cluster ready. Run 'make status' to check deployment health."

stop: ## Pause minikube between sessions — stops port-forwards and preserves all data
	@bash scripts/port-forward-stop.sh
	minikube stop -p $(PROFILE)
	@echo "Cluster paused. Resume with 'make start'."

down: ## Remove Mattermost CR only — keeps the cluster, PVCs, and operator intact
	@bash scripts/down.sh

reset: down run ## Tear down and redeploy Mattermost (database data is preserved in PVC)

do-nuke: ## DESTRUCTIVE: delete the minikube cluster and ALL data (requires CONFIRM=yes)
	@[ "$(CONFIRM)" = "yes" ] || \
	  (printf "\033[31mSet CONFIRM=yes to confirm deletion of cluster '$(PROFILE)'\033[0m\n" && exit 1)
	minikube delete -p $(PROFILE)
	@echo "Cluster '$(PROFILE)' deleted."

# ─── OPERATIONS ──────────────────────────────────────────────────────────────

logs: ## Stream Mattermost pod logs (Ctrl+C to exit)
	$(KUBECTL) -n $(NAMESPACE) logs -f \
	  -l app=mattermost \
	  --all-containers=true --prefix=true

status: ## Show pod health, Mattermost CR status, and resource overview
	@bash scripts/status.sh

echo-logins: ## Print all access URLs, ports, and credentials
	@bash scripts/status.sh --logins

port-forward: ## (Re-)start background port-forwards (Mattermost :8065, MailHog :8025, MinIO :9001)
	@printf "\n\033[1mPort-forwards:\033[0m\n"
	@bash scripts/port-forward.sh

port-forward-stop: ## Stop background port-forwards
	@bash scripts/port-forward-stop.sh

tunnel: ## Start minikube tunnel for ingress access (may prompt for elevated privileges)
	@echo "Tunnel running — access Mattermost at http://$(MM_DOMAIN)"
	@echo "Ensure '$(MM_DOMAIN)' is in /etc/hosts (run 'make hosts' for instructions)"
	minikube tunnel -p $(PROFILE)

hosts: ## Print the /etc/hosts line needed for ingress-based access
	@printf "\nAdd this line to your hosts file:\n\n"
	@printf "  \033[33m$$(minikube ip -p $(PROFILE))\t$(MM_DOMAIN)\033[0m\n\n"
	@printf "Windows path: C:\\Windows\\System32\\drivers\\etc\\hosts\n"
	@printf "Linux/Mac:    /etc/hosts\n\n"

shell: ## Open a bash shell in the running Mattermost pod
	$(KUBECTL) -n $(NAMESPACE) exec -it \
	  $$($(KUBECTL) -n $(NAMESPACE) get pod \
	    -l app=mattermost \
	    -o jsonpath='{.items[0].metadata.name}') \
	  -- /bin/bash

upgrade: ## Change the running Mattermost version (usage: make upgrade MM_VERSION=10.6.0)
	@echo "Patching Mattermost CR → version $(MM_VERSION)"
	$(KUBECTL) -n $(NAMESPACE) patch mattermost mattermost \
	  --type=merge -p "{\"spec\":{\"version\":\"$(MM_VERSION)\"}}"
	@echo "Upgrade in progress. Watch with: make status"

# ─── INTERNAL ────────────────────────────────────────────────────────────────

.env-check:
	@[ -f .env ] || \
	  (printf "\033[31mNo .env file found.\033[0m Run: cp .env.example .env\n" && exit 1)
