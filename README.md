# Mattermost Kubernetes Repro Environment

A local Kubernetes reproduction environment for Mattermost, built on [minikube](https://minikube.sigs.k8s.io/) and the [Mattermost Kubernetes Operator](https://docs.mattermost.com/deployment-guide/server/deploy-kubernetes.html). Modeled after [CS-Repro-Mattermost](https://github.com/coltoneshaw/CS-Repro-Mattermost) for Kubernetes-based deployments.

The cluster persists across sessions — `make stop` pauses it and `make start` resumes it with all data intact. Use this for deep multi-session debugging without losing state.

## Architecture

```
minikube (profile: mm-repro)
└── namespace: mattermost
    ├── Mattermost Operator          (mattermost-operator namespace)
    ├── Mattermost (CR)              ← managed by operator
    │     └── Deployment + Service + Ingress
    ├── PostgreSQL 16                StatefulSet + PVC (10Gi)
    ├── MinIO                        StatefulSet + PVC (10Gi) — S3-compatible filestore
    └── MailHog                      Deployment — catches all outbound SMTP
```

Optional add-ons (deployed separately):
- **OpenLDAP** — pre-seeded with test users for AD/LDAP repro
- **Prometheus + Grafana** — kube-prometheus-stack for metrics repro

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| minikube | ≥ 1.32 | [minikube.sigs.k8s.io](https://minikube.sigs.k8s.io/docs/start/) |
| kubectl | ≥ 1.28 | bundled with Docker Desktop or [k8s.io/docs/tasks/tools](https://kubernetes.io/docs/tasks/tools/) |
| helm | ≥ 3.13 | [helm.sh/docs/intro/install](https://helm.sh/docs/intro/install/) |
| GNU make | any | Git for Windows includes it; or `winget install GnuWin32.Make` |
| bash | any | WSL2, Git Bash, or any POSIX shell |

Docker Desktop must be running before starting minikube (default driver: `docker`).

## Quick Start

```bash
# 1. Configure (only needed once)
cp .env.example .env

# 2. One-time setup: start minikube, install operator, deploy infrastructure
make setup

# 3. Deploy Mattermost — port-forwards start automatically when ready
make run
# → Mattermost (HTTPS): https://localhost:8443  ← self-signed cert; see below
# → Mattermost (HTTP):  http://localhost:8065   ← direct, no cert warning
# → MailHog:            http://localhost:8025
# → MinIO console:      http://localhost:9001
```

First visit will prompt you to create an admin account. Use `https://localhost:8443` for HTTPS (your browser will warn about the self-signed certificate — click through or import `.tls/tls.crt` as a trusted CA to silence it). Use `http://localhost:8065` for quick access without the cert warning.

## Session Workflow

```
# Start of session
make start          # Resume cluster + restart port-forwards automatically

# Work...
make logs           # Stream Mattermost logs
make status         # Health overview + pod list
make shell          # bash into the Mattermost pod

# End of session
make stop           # Stop port-forwards + pause cluster (data preserved)
```

The cluster is a named minikube profile (`mm-repro` by default), so it coexists with any default minikube clusters you use elsewhere.

## Deployment Variants

| Command | Description |
|---------|-------------|
| `make run` | Single Mattermost replica (default) |
| `make run-ha` | 2 replicas with clustering (requires Enterprise license) |
| `make run-ldap` | Adds OpenLDAP with pre-seeded test users |
| `make run-monitoring` | Adds Prometheus + Grafana |
| `make run-all` | Everything above |

## Enterprise License

Place your license file at `license.mattermost` in the repo root (it is gitignored). Then:

```bash
make generate-secrets   # loads it into a Kubernetes secret
make reset              # redeploys Mattermost with the license
```

Without a license the environment runs Team Edition (sufficient for most repro work that doesn't require Enterprise features).

## Upgrading / Downgrading Mattermost

```bash
# Upgrade — operator handles migration automatically
make upgrade MM_VERSION=10.6.0

# Downgrade — set the version back (operator handles this too)
make upgrade MM_VERSION=10.4.1

# Or edit .env and reset
# MM_VERSION=10.4.1
make reset
```

## Ingress Access (DNS-based)

Port-forwarding works for most repro scenarios. For cases that require a proper hostname (SSO callbacks, webhook URLs, etc.):

```bash
# 1. Get the line to add to your hosts file
make hosts
# Outputs something like: 192.168.49.2   mattermost.local

# 2. Add it to your hosts file:
#    Windows: C:\Windows\System32\drivers\etc\hosts (requires admin)
#    Linux/Mac: /etc/hosts

# 3. Start the tunnel (keeps ingress routing active)
make tunnel
```

Then access Mattermost at `https://mattermost.local`. The TLS certificate is generated automatically by `make setup` / `make generate-secrets` — import `.tls/tls.crt` as a trusted CA in your browser to avoid the self-signed cert warning.

## Resetting vs Nuking

| Action | Command | Preserves data? |
|--------|---------|-----------------|
| Redeploy Mattermost only | `make reset` | Yes — DB and files intact |
| Remove Mattermost CR | `make down` | Yes |
| Delete entire cluster | `CONFIRM=yes make do-nuke` | No — everything gone |

`make reset` is the fastest way to reproduce a clean deployment state without losing your database. The PostgreSQL and MinIO PVCs survive until `do-nuke`.

## LDAP Test Credentials

`make run-ldap` deploys OpenLDAP, waits for it to be ready, and then automatically configures all Mattermost LDAP settings via `mmctl` — no System Console steps required. It uses the [CS-Repro-Mattermost](https://github.com/coltoneshaw/CS-Repro-Mattermost) setup with Futurama characters pre-seeded by the image, plus a seed job that adds the Robot Mafia users.

Run `make ldap-configure` to re-apply settings or trigger a sync at any time.

**Connection settings** (applied automatically — shown here for reference)

| Field | Value |
|-------|-------|
| Server | `openldap.mattermost.svc.cluster.local` |
| Port | `389` |
| Base DN | `dc=planetexpress,dc=com` |
| Bind DN | `cn=admin,dc=planetexpress,dc=com` |
| Bind password | `GoodNewsEveryone` |
| User filter | `(objectClass=Person)` |
| Group filter | `(objectClass=Group)` |
| Username attribute | `uid` |
| ID attribute | `uid` |
| Email attribute | `mail` |
| First name attribute | `givenName` |
| Last name attribute | `sn` |
| Profile picture attribute | `jpegPhoto` |
| Group display name attribute | `cn` |
| Group ID attribute | `cn` |
| Admin filter | `(memberof=cn=admin_staff,ou=people,dc=planetexpress,dc=com)` |

**Users** — all under `ou=people,dc=planetexpress,dc=com`

| uid | Display name | Password | Notes |
|-----|-------------|----------|-------|
| `professor` | Hubert J. Farnsworth | `professor` | System Admin via `admin_staff` |
| `hermes` | Hermes Conrad | `hermes` | System Admin via `admin_staff` |
| `fry` | Philip J. Fry | `fry` | |
| `leela` | Turanga Leela | `leela` | |
| `bender` | Bender Bending Rodríguez | `bender` | |
| `zoidberg` | John A. Zoidberg | `zoidberg` | |
| `amy` | Amy Wong | `amy` | |
| `dsmith` | Donbot Smith | `dsmith` | Added by seed job |
| `jmousepad` | Joey Mousepad | `jmousepad` | Added by seed job |

**Groups**

| Group | Members |
|-------|---------|
| `admin_staff` | professor, hermes |
| `ship_crew` | leela, fry, bender (+ dsmith, jmousepad after seed job) |
| `robot_mafia` | dsmith, jmousepad |

The admin filter automatically promotes `professor` and `hermes` to Mattermost System Admin on LDAP sync.

> **After an OpenLDAP pod restart**, the 7 Futurama characters and the `admin_staff`/`ship_crew` groups are restored automatically (baked into the image). Run `make ldap-seed` to re-add the Robot Mafia users.

## Cluster Inspection

All `kubectl` commands target this cluster via the `mm-repro` context. Either set it as your active context once, or pass `--context mm-repro` on every command.

```bash
# Set as active context (persists until you switch again)
kubectl config use-context mm-repro

# Or pass it per-command (safer when juggling multiple clusters)
kubectl --context mm-repro <subcommand>
```

**List namespaces**
```bash
kubectl --context mm-repro get namespaces
```

Key namespaces:
- `mattermost` — Mattermost app, PostgreSQL, MinIO, MailHog, and optional add-ons
- `mattermost-operator` — the operator that manages the Mattermost CR
- `ingress-nginx` — ingress controller (created by `make setup`)

**List pods**
```bash
# Pods in the mattermost namespace
kubectl --context mm-repro -n mattermost get pods

# All namespaces at once
kubectl --context mm-repro get pods -A
```

**Exec into a pod**
```bash
# Shortcut — drops you into a shell on the Mattermost app pod
make shell

# Manual — works for any pod (postgres, minio, mailhog, etc.)
kubectl --context mm-repro -n mattermost exec -it <pod-name> -- bash

# Example: find and exec into the Postgres pod
kubectl --context mm-repro -n mattermost get pods -l app=postgres
kubectl --context mm-repro -n mattermost exec -it <postgres-pod-name> -- bash
```

Inside the Mattermost pod, `config.json` is at `/mattermost/config/config.json` and `mmctl` is available on the PATH.

## Troubleshooting

**Pods stuck in `Pending`**
```bash
kubectl --context mm-repro -n mattermost describe pod <pod-name>
# Usually a resource constraint — increase MINIKUBE_CPUS/MINIKUBE_MEMORY in .env
# then: CONFIRM=yes make do-nuke && make setup && make run
```

**Mattermost CR stays in `reconciling` state**
```bash
# Check operator logs
kubectl --context mm-repro -n mattermost-operator logs -l app.kubernetes.io/name=mattermost-operator
# Check Mattermost pod events
kubectl --context mm-repro -n mattermost describe mattermost mattermost
```

**Database connection errors**
```bash
# Verify Postgres is running
kubectl --context mm-repro -n mattermost get pod -l app=postgres
# Regenerate secrets (useful after changing DB creds in .env)
make generate-secrets && make reset
```

**MinIO bucket missing**
```bash
# The init container creates the bucket on first start — check its logs
kubectl --context mm-repro -n mattermost logs -l app=minio -c create-bucket
```

**Port-forward drops / connection refused**
```bash
# Port-forwards die if a pod restarts — re-run to restore them
make port-forward
```

**Windows: `make` not found**
```
winget install GnuWin32.Make
# or use Git Bash which includes make
```

## Directory Structure

```
.
├── Makefile                     # All commands — start here
├── .env.example                 # Configuration template
├── config/
│   └── operator-values.yaml     # Helm values for Mattermost Operator
├── manifests/
│   ├── core/                    # Always deployed (namespace, postgres, minio, mailhog)
│   ├── mattermost/
│   │   ├── installation.yaml    # Single-replica CR (envsubst template)
│   │   └── installation-ha.yaml # HA CR (2 replicas, requires license)
│   └── optional/
│       └── ldap.yaml            # OpenLDAP + test user seed job
└── scripts/
    ├── setup.sh                 # One-time bootstrap
    ├── generate-secrets.sh      # Create K8s secrets from .env
    ├── up.sh                    # Deploy Mattermost CR
    ├── down.sh                  # Remove Mattermost CR
    ├── port-forward.sh          # Local port exposure
    └── status.sh                # Health + credentials overview
```
