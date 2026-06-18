# Kagenti Full Platform — Setup Guide

## Environment Facts (Verified)

| Item | Value |
|---|---|
| macOS RAM | 36 GB |
| Podman machine (`podman-machine-default`) | libkrun, currently **2 GB** RAM, 7 CPUs, 100 GB disk |
| `podman machine set --memory` | Requires machine to be **stopped** first |
| `kind` | v0.31.0 — installed ✅ |
| `helm` | v4.0.5 — installed ✅ |
| `kubectl` | ≥1.32 — installed ✅ |
| Kagenti version | `v0.7.0-alpha.3` |
| Kagenti Operator chart version | `0.2.0-alpha.24` (local source), `0.3.0-alpha.5` (bundled in kagenti chart) |
| Kagenti UI image | `ghcr.io/kagenti/kagenti/ui-v2:v0.7.0-alpha.3` — **public** ✅ |
| Kagenti backend image | `ghcr.io/kagenti/kagenti/backend:v0.7.0-alpha.3` — **public** ✅ |
| Kagenti Operator image | `ghcr.io/kagenti/kagenti-operator/kagenti-operator` — **private** ❌ (must build from source) |
| cert-manager version | `v1.17.2` |
| Istio version | `1.28.0` |
| SPIRE version | `0.27.0` |
| Gateway API version | `v1.4.0` |
| Hello Kagenti Agent | Built and confirmed working |

---

## Why the Cluster Is Currently Down

The `minikube-1` profile lost its underlying Podman container (Podman Desktop restart or machine reset). The context `minikube-1` no longer exists. All three paths below start from scratch with correct sizing.

---

## Three Paths to the Full Kagenti Platform

| | Path A | Path B | Path C |
|---|---|---|---|
| **What** | Resize Podman machine → new minikube | Dedicated Kind cluster | Keycloak only (auth, no UI) |
| **UI included** | ✅ Yes | ✅ Yes | ❌ No |
| **Zero-Trust (SPIRE)** | Optional | Optional | ❌ No |
| **RAM needed** | 8 GB on Podman machine | 8 GB on Podman machine | 2 GB (current) |
| **Script** | `scripts/setup-full-platform.sh` | `scripts/setup-kind-platform.sh` | Manual (3 commands) |
| **Access URL** | `http://kagenti-ui.localtest.me:8080` | `http://kagenti-ui.localtest.me:8080` | Keycloak NodePort only |

---

## Path A — Resize Podman Machine + New minikube + Kagenti (Recommended)

### Step 1 — Resize the Podman machine

> `podman machine set` requires the machine to be **stopped**. Your Mac has 36 GB RAM so 12 GB is safe.

```bash
podman machine stop podman-machine-default
podman machine set --memory 12288 --cpus 6 podman-machine-default
podman machine start podman-machine-default

# Verify
podman machine list
# NAME                    VM TYPE   CPUS   MEMORY   ...
# podman-machine-default  libkrun   6      12GiB
```

### Step 2 — Delete the stale minikube-1 profile and recreate

```bash
minikube delete --profile minikube-1 2>/dev/null || true

minikube start \
  --profile minikube-1 \
  --driver=podman \
  --container-runtime=cri-o \
  --memory=8192 \
  --cpus=4

# Confirm context
kubectl config use-context minikube-1
kubectl get nodes
```

### Step 3 — Clone the Kagenti repo

```bash
cd /tmp
git clone https://github.com/kagenti/kagenti.git
cd kagenti
git checkout v0.7.0-alpha.3   # pin to the version whose images we know are public
```

### Step 4 — Run the Kagenti setup script (reuse existing cluster)

```bash
# --skip-cluster reuses the current kubectl context (minikube-1)
# --with-ui auto-enables backend
# No --with-istio or --with-spire to stay within 8 GB
CONTAINER_ENGINE=podman \
  scripts/kind/setup-kagenti.sh \
    --skip-cluster \
    --with-ui \
    --with-backend
```

> **What `--skip-cluster` does:** skips `kind create cluster`, uses whatever `kubectl cluster-info` resolves to — which is `minikube-1` after `kubectl config use-context minikube-1`.

### Step 5 — Redeploy your Hello Kagenti Agent

```bash
cd /Users/alainairom/Devs/kagenti-test/kagenti-hello-agent

# Rebuild and reload image (cluster is fresh)
./scripts/build-and-deploy.sh
```

### Step 6 — Access the UI

```bash
# The setup script configures NodePort 30080 → host:8080 via minikube tunnelling.
# For minikube you need minikube tunnel or a port-forward instead:
kubectl port-forward svc/kagenti-ui 8080:8080 -n kagenti-system --context minikube-1 &

open http://localhost:8080
```

> **Credentials:** run `.github/scripts/local-setup/show-services.sh` from the cloned Kagenti repo, or check the `keycloak-initial-admin` secret:
>
> ```bash
> kubectl get secret keycloak-initial-admin -n keycloak \
>   --context minikube-1 -o jsonpath='{.data.password}' | base64 -d
> ```

---

## Path B — Dedicated Kind Cluster + Full Kagenti (Cleanest)

Kind is already installed (`kind v0.31.0`). This path creates a **separate** cluster and does not touch your Podman machine sizing for the agent work.

### Step 1 — Resize the Podman machine (same as Path A Step 1)

```bash
podman machine stop podman-machine-default
podman machine set --memory 12288 --cpus 6 podman-machine-default
podman machine start podman-machine-default
```

### Step 2 — Clone the Kagenti repo

```bash
cd /tmp
git clone https://github.com/kagenti/kagenti.git
cd kagenti
git checkout v0.7.0-alpha.3
```

### Step 3 — Run the Kagenti setup script (creates Kind cluster)

```bash
# Creates a Kind cluster named "kagenti" with NodePort 30080→host:8080
# --with-ui auto-enables backend
CONTAINER_ENGINE=podman \
  scripts/kind/setup-kagenti.sh \
    --with-ui \
    --with-backend
    # Optionally add:
    # --with-spire        (Zero-Trust workload identity — needs ~12 GB)
    # --with-istio        (mTLS ambient mesh — needs ~14 GB)
    # --with-all          (everything — needs 18 GB)
```

The script:
1. Creates a Kind cluster `kagenti` with Podman as the container engine
2. Installs cert-manager `v1.17.2`
3. Installs Istio Gateway controller `1.28.0` (base + istiod — always, even without `--with-istio`)
4. Installs Gateway API CRDs `v1.4.0`
5. Installs Keycloak (via `kagenti-deps` Helm chart)
6. Installs Kagenti Operator, webhook, UI, backend (via `kagenti` Helm chart)

### Step 4 — Access the UI

The Kind config maps `containerPort 30080` → `hostPort 8080`:

```bash
open http://kagenti-ui.localtest.me:8080
```

> `localtest.me` always resolves to `127.0.0.1` — no `/etc/hosts` changes needed.

### Step 5 — Show credentials

```bash
cd /tmp/kagenti
.github/scripts/local-setup/show-services.sh
```

### Step 6 — Redeploy your Hello Kagenti Agent into the Kind cluster

```bash
cd /Users/alainairom/Devs/kagenti-test/kagenti-hello-agent

# Build image and load into Kind (not minikube)
podman build --platform linux/arm64 \
  -t localhost/hello-kagenti-agent:1.0.0 \
  -f Dockerfile .

podman save localhost/hello-kagenti-agent:1.0.0 -o /tmp/hello-agent.tar
kind load image-archive /tmp/hello-agent.tar --name kagenti

kubectl apply -f k8s/deploy.yaml --context kind-kagenti
kubectl rollout status deployment/hello-kagenti-agent -n team1 --context kind-kagenti
```

---

## Path C — Keycloak Only on Current Cluster (No UI, Proves Auth Chain)

This path requires **no Podman machine resize** — it fits in 2 GB. It unblocks the Kagenti Operator's `clientregistration` controller which is currently logging:

```
waiting for KEYCLOAK_URL/KEYCLOAK_REALM in authbridge-config
```

### Step 1 — Recreate minikube-1 (2 GB is enough for Keycloak alone)

```bash
minikube delete --profile minikube-1 2>/dev/null || true

minikube start \
  --profile minikube-1 \
  --driver=podman \
  --container-runtime=cri-o \
  --memory=2048 \
  --cpus=4

kubectl config use-context minikube-1
```

### Step 2 — Reinstall cert-manager and Kagenti Operator

```bash
# cert-manager
kubectl apply -f \
  https://github.com/cert-manager/cert-manager/releases/download/v1.17.2/cert-manager.yaml
kubectl rollout status deployment/cert-manager-webhook -n cert-manager --timeout=120s

# Kagenti Operator (from local source — already built)
podman save localhost/kagenti-operator:v0.2.0-alpha.24 -o /tmp/kagenti-operator.tar
minikube image load /tmp/kagenti-operator.tar --profile minikube-1

helm install kagenti-operator \
  /Users/alainairom/Devs/kagenti-test/_sources/kagenti-operator-src/kagenti-operator-main/charts/kagenti-operator \
  --namespace kagenti-system --create-namespace \
  --kube-context minikube-1 \
  --set controllerManager.container.image.repository=localhost/kagenti-operator \
  --set controllerManager.container.image.tag=v0.2.0-alpha.24 \
  --set controllerManager.container.image.pullPolicy=Never \
  --set metrics.enable=false
```

### Step 3 — Install Keycloak

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update bitnami

helm install keycloak bitnami/keycloak \
  --namespace keycloak --create-namespace \
  --kube-context minikube-1 \
  --set auth.adminUser=admin \
  --set auth.adminPassword=admin \
  --set service.type=NodePort \
  --set service.nodePorts.http=30082 \
  --timeout 5m
```

### Step 4 — Patch the Kagenti Operator to point at Keycloak

```bash
KEYCLOAK_URL=$(minikube service keycloak -n keycloak --url --profile minikube-1 2>/dev/null | head -1)

helm upgrade kagenti-operator \
  /Users/alainairom/Devs/kagenti-test/_sources/kagenti-operator-src/kagenti-operator-main/charts/kagenti-operator \
  --namespace kagenti-system \
  --kube-context minikube-1 \
  --reuse-values \
  --set keycloak.adminSecretNamespace=keycloak \
  --set keycloak.realm=kagenti \
  --set "keycloak.publicUrl=${KEYCLOAK_URL}"
```

### Step 5 — Redeploy the Hello Kagenti Agent

```bash
cd /Users/alainairom/Devs/kagenti-test/kagenti-hello-agent
./scripts/build-and-deploy.sh
```

### Step 6 — Verify the auth chain

```bash
# Operator should now reconcile clientregistration without errors
kubectl logs -n kagenti-system -l control-plane=controller-manager \
  --context minikube-1 --tail=20

# AgentRuntime and AgentCard should still be Ready
kubectl get agentruntimes,agentcards -n team1 --context minikube-1
```

---

## Service URLs (after Path A or B)

| Service | URL | Notes |
|---|---|---|
| **Kagenti UI** | `http://kagenti-ui.localtest.me:8080` | Login with Keycloak credentials |
| **Kagenti API** | `http://kagenti-api.localtest.me:8080` | REST backend |
| **Keycloak** | `http://keycloak.localtest.me:8080` | Admin console |
| **Hello Agent** | `http://localhost:18000` (via port-forward) | A2A JSON-RPC |
| MLflow (if `--with-mlflow`) | `http://mlflow.localtest.me:8080` | Trace UI |
| Tornjak (if `--with-spire`) | `http://spire-tornjak-ui.localtest.me:8080` | SPIFFE identity UI |

> `localtest.me` always resolves to `127.0.0.1` — works on any machine without `/etc/hosts` edits.

---

## RAM Budget Reference

| Configuration | RAM needed |
|---|---|
| cert-manager + Operator + agent (current, no UI) | ~2 GB |
| + Keycloak (Path C) | ~3 GB |
| + Keycloak + UI + backend (Path A/B minimal) | ~5–6 GB |
| + Istio Gateway controller (always in script core) | ~7 GB |
| + SPIRE (`--with-spire`) | ~9 GB |
| + Istio ambient mesh (`--with-istio`) | ~11 GB |
| + MLflow + OTel + Kiali (`--with-all`) | ~18 GB |

**Podman machine recommendation:** `12 GB` — covers UI + Keycloak + SPIRE with headroom. `8 GB` covers UI + Keycloak only.
