# Kagenti UI & Full Platform — Assessment Report
_Generated: 2026-06-17 12:10 CET_

---

## Short Answer

**Yes, a Kagenti UI exists — but it cannot run on your current minikube cluster as-is.**  
Your minikube node has **~2 GB RAM**. The full Kagenti stack (Keycloak + Istio + SPIRE + UI + backend) requires **18 GB RAM / 6 CPUs** (Kind cluster). A minimal useful subset (UI + backend + Keycloak, no Istio/SPIRE) could fit in ~6–8 GB.

---

## What the Full Kagenti Platform Provides

```
┌────────────────────────────────────────────────────────┐
│                   KAGENTI PLATFORM                     │
├────────────────────────────────────────────────────────┤
│  KAGENTI UI  (http://kagenti-ui.localtest.me:8080)     │
│  → Deploy agents/tools, interactive testing, traces    │
├────────────────────────────────────────────────────────┤
│  WORKLOAD RUNTIME                                      │
│  Agents (A2A)  │  Tools (MCP)  │  Skills              │
├───────────┬────┴──────────┬─────┴───────┬──────────────┤
│ LIFECYCLE │  NETWORKING   │  SECURITY   │ OBSERVABILITY│
│ Operator  │  Istio mesh   │  SPIRE/SPIFFE│  MLflow      │
│ Webhook   │  MCP Gateway  │  Keycloak   │  Phoenix     │
│ Shipwright│  Kuadrant     │  AuthBridge │  Kiali       │
└───────────┴───────────────┴─────────────┴──────────────┘
          KUBERNETES / OPENSHIFT (bottom layer)
```

### Component Breakdown

| Component | Image | Public? | What it does |
|---|---|---|---|
| **Kagenti UI** | `ghcr.io/kagenti/kagenti/ui-v2:v0.7.0-alpha.3` | ✅ Yes | React dashboard — deploy agents, test interactively, view traces |
| **Backend API** | `ghcr.io/kagenti/kagenti/backend:v0.7.0-alpha.3` | ✅ Yes | REST API behind the UI, manages agent lifecycle |
| **Keycloak** | `quay.io/keycloak/keycloak:26.x` | ✅ Yes | OAuth2/OIDC — AuthN/AuthZ for all agents |
| **AuthBridge sidecar** | `ghcr.io/kagenti/kagenti-extensions/authbridge:latest` | ✅ Yes | JWT validation + token exchange proxy injected into agent pods |
| **SPIRE** | `ghcr.io/spiffe/spire-server` / `spire-agent` | ✅ Yes | Zero-trust workload identity (SVID / X.509 certs per pod) |
| **Istio (ambient)** | `docker.io/istio/*` | ✅ Yes | mTLS service mesh for all inter-agent traffic |
| **MCP Gateway** | `ghcr.io/kuadrant/mcp-gateway` | ✅ Yes | Policy-enforcing gateway for MCP tools |
| **Kagenti Operator** | `ghcr.io/kagenti/kagenti-operator/kagenti-operator` | ❌ Private | Must build from source (already done for you) |

---

## What We Already Have vs. What Is Missing

### ✅ Already Running on Your Cluster

| Component | Namespace | Status |
|---|---|---|
| cert-manager | `cert-manager` | `3/3 Running` |
| Kagenti Operator (from source) | `kagenti-system` | `1/1 Running` |
| Hello Kagenti Agent | `team1` | `1/1 Running` |
| AgentRuntime CR | `team1` | `Ready=True` |
| AgentCard CR | `team1` | `Synced=True` |

### ❌ Missing for Full Platform

| Component | Required For | Blocker? |
|---|---|---|
| **Keycloak** | Auth, UI login, OIDC tokens | Operator waits for it (non-fatal, logged as `clientregistration` warning) |
| **Kagenti Backend API** | UI functionality | Yes — UI calls backend |
| **Kagenti UI** | Dashboard | Needs backend |
| **Istio** | mTLS mesh, AuthBridge injection | Optional for basic agent operation |
| **SPIRE** | Zero-trust workload identity | Optional (disables SVID-based AuthBridge) |
| **MCP Gateway** | MCP tool routing | Optional |
| **Ingress / Gateway API** | External access to UI | Needed to reach UI from browser |
| **More RAM** | Everything above | **Current: ~2 GB — Need: 6–18 GB** |

---

## Why the Full Platform Needs More Resources

The Kagenti setup script is explicit:

```
RECOMMENDED_MEMORY_MB=18432   # 18 GB
RECOMMENDED_CPUS=6
```

Your current minikube node:

```
cpu:    7 cores          ✅ sufficient
memory: 1,988,064 Ki     ❌ ~2 GB — way under the 18 GB recommendation
```

### Minimum Viable Subset (UI + Auth, no Istio/SPIRE)

| Component | RAM estimate |
|---|---|
| cert-manager | ~128 MB |
| Kagenti Operator | ~128 MB |
| Keycloak | ~512 MB |
| Backend API | ~256 MB |
| Kagenti UI (nginx) | ~64 MB |
| Ingress controller | ~128 MB |
| **Total** | **~1.2–1.5 GB headroom needed** |

This minimal subset would need a minikube node with **at least 4–6 GB RAM**.

---

## How to Get the Full Stack Running

### Option A — Resize your minikube cluster (recommended)

```bash
# Stop the current profile
minikube stop --profile minikube-1

# Delete and recreate with more RAM (minimum for UI + Keycloak, no Istio)
minikube delete --profile minikube-1
minikube start \
  --profile minikube-1 \
  --driver=podman \
  --container-runtime=cri-o \
  --memory=8192 \
  --cpus=4

# Then run the Kagenti setup script on your existing cluster
cd /path/to/kagenti   # cloned from https://github.com/kagenti/kagenti
scripts/kind/setup-kagenti.sh \
  --skip-cluster \
  --with-ui \
  --with-backend
  # --with-spire       # adds Zero-Trust (needs more RAM)
  # --with-istio       # adds mTLS mesh (needs more RAM)
```

> **Note:** `--skip-cluster` tells the script to reuse your existing kubectl context instead of creating a new Kind cluster.

### Option B — Create a dedicated Kind cluster (fully supported path)

```bash
# Install kind
brew install kind

# Run the Kagenti installer — creates its own Kind cluster
cd /path/to/kagenti
scripts/kind/setup-kagenti.sh \
  --with-ui \
  --with-spire \
  --with-backend

# Access the UI
open http://kagenti-ui.localtest.me:8080
```

### Option C — Add Keycloak only (minimal auth, no UI)

This unblocks the Operator's `clientregistration` controller and proves the auth chain:

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install keycloak bitnami/keycloak \
  --namespace keycloak --create-namespace \
  --set auth.adminUser=admin \
  --set auth.adminPassword=admin \
  --set service.type=NodePort \
  --kube-context minikube-1
```

---

## What the Kagenti UI Gives You (Once Running)

From the README and UI source:

```
http://kagenti-ui.localtest.me:8080
```

Features:
- **Agent deployment** — Import A2A agents from any framework (LangGraph, CrewAI, plain Python) — no framework lock-in
- **Tool deployment** — Deploy MCP servers directly from GitHub source or image
- **Interactive testing** — Chat with any deployed agent in the browser
- **Trace monitoring** — View MLflow / Phoenix / OTel traces for agent calls
- **Network visualization** — Kiali graph of agent-to-agent traffic (with Istio)
- **Agent discovery** — All agents registered via `AgentRuntime` CR appear automatically

---

## Summary

| Question | Answer |
|---|---|
| Does a Kagenti UI exist? | ✅ Yes — `ghcr.io/kagenti/kagenti/ui-v2:v0.7.0-alpha.3`, publicly available |
| Can it run on your current minikube? | ❌ No — only ~2 GB RAM available |
| Is your agent already integrated into Kagenti? | ✅ Yes — `AgentCard` and `AgentRuntime` are `Ready=True`, operator is running |
| Is Zero-Trust / Auth working? | ⚠️ Partially — Operator is installed, but Keycloak (OIDC) and SPIRE (workload identity) are not deployed yet |
| What's the fastest path to the UI? | Resize minikube to 8 GB and run `setup-kagenti.sh --skip-cluster --with-ui` |
