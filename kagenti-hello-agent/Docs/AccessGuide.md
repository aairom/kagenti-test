# Access Guide — Hello Kagenti Agent

How to reach every UI, API, and service running in the local minikube cluster.

---

## How routing works

All platform UIs are served by a single **Istio Ingress Gateway** via **hostname-based routing**
(`localtest.me`). The domain `localtest.me` always resolves to `127.0.0.1` — so a single
`kubectl port-forward` exposes every service at once.

```
Your Browser
    │
    │  http://kagenti-ui.localtest.me:19080
    │  http://kagenti-api.localtest.me:19080
    │  http://keycloak.localtest.me:19080
    ▼
localhost:19080   ←── kubectl port-forward ──►  svc/http-istio-np :80
                                                       (kagenti-system)
                                                            │
                                         Istio Gateway (NodePort 30080)
                                                            │
                              ┌─────────────────────────────────────────┐
                              │  HTTPRoute hostname matching             │
                              │  kagenti-ui.localtest.me → UI :8080     │
                              │  kagenti-api.localtest.me → Backend:8000│
                              │  keycloak.localtest.me → Keycloak:8080  │
                              └─────────────────────────────────────────┘
```

> **Why not use the minikube node IP directly?**
> The minikube node IP (`192.168.49.2`) is inside the Podman VM and is **not reachable** from
> macOS when using the Podman driver. `kubectl port-forward` is the only access method.

> **Why port 19080 and not 8080?**
> Port 8080 is already in use on this machine. Port 19080 is free.

---

## Step 1 — Start the gateway port-forward (required for all UIs)

Open a **dedicated terminal** and keep this running:

```bash
kubectl --context minikube-1 port-forward \
  -n kagenti-system svc/http-istio-np 19080:80
```

You'll see:
```
Forwarding from 127.0.0.1:19080 -> 80
Forwarding from [::1]:19080 -> 80
```

Leave this terminal open. All URLs below require it.

---

## Available UIs

### 1. Kagenti Agents Dashboard

| | |
|---|---|
| URL | `http://kagenti-ui.localtest.me:19080` |
| Auth | Disabled (`ui.auth.enabled: false`) — no login needed |
| What you see | Agent list, AgentCard detail, runtime status |

The **Agents tab** shows `hello-kagenti-agent` with:
- Protocol: `a2a`
- Kind: `Deployment`
- Synced: `True`
- Skills: Greeting Skill

### 2. Kagenti REST API

| | |
|---|---|
| URL | `http://kagenti-api.localtest.me:19080/api/v1/agents` |
| Auth | None |

```bash
# List all registered agents
curl -s http://kagenti-api.localtest.me:19080/api/v1/agents \
  | python3 -m json.tool
```

### 3. Keycloak Admin Console

| | |
|---|---|
| URL | `http://keycloak.localtest.me:19080` |
| Auth | Admin credentials from Helm values |

Keycloak manages identity for the Kagenti platform. Auth is currently disabled for the UI,
so Keycloak is only needed if you enable `ui.auth.enabled: true`.

---

## Step 2 — Agent direct access (for testing)

Open a **second terminal**:

```bash
kubectl --context minikube-1 port-forward \
  -n team1 svc/hello-kagenti-agent 18000:8000
```

### Endpoints

| Endpoint | Method | Description |
|---|---|---|
| `/health` | GET | Health check → `{"status":"ok"}` |
| `/.well-known/agent-card.json` | GET | A2A AgentCard (name, skills, version) |
| `/` | POST | A2A JSON-RPC (`message/send`) |

### Quick tests

```bash
# Health
curl http://localhost:18000/health

# Agent Card
curl http://localhost:18000/.well-known/agent-card.json | python3 -m json.tool

# Send a message (A2A JSON-RPC)
curl -s -X POST http://localhost:18000/ \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": "1",
    "method": "message/send",
    "params": {
      "message": {
        "messageId": "msg-001",
        "role": "user",
        "parts": [{"kind": "text", "text": "Hello! My name is Alice."}]
      }
    }
  }' | python3 -m json.tool
```

Or run the automated test script:

```bash
cd kagenti-hello-agent
./scripts/test-agent.sh
```

---

## Observability

### What the Kagenti UI shows

The **Observability tab** in the Kagenti UI currently shows:
> *"Ensure that the observability tools (Kiali for service mesh) are properly configured
> and accessible from your environment."*

This is expected — Kiali is disabled in the current deployment.

### Immediate observability (no extra tools)

**Agent logs** — see every incoming message and LLM response in real time:

```bash
kubectl --context minikube-1 logs -f \
  -l app.kubernetes.io/name=hello-kagenti-agent \
  -n team1
```

**Operator logs** — watch reconciliation events (AgentRuntime → AgentCard):

```bash
kubectl --context minikube-1 logs -f \
  -l app.kubernetes.io/name=kagenti-operator-chart \
  -n kagenti-system
```

**Cluster-wide status:**

```bash
# All pods across all namespaces
kubectl --context minikube-1 get pods -A

# AgentCard status
kubectl --context minikube-1 get agentcards -n team1

# AgentRuntime status
kubectl --context minikube-1 get agentruntimes -n team1
```

### Enable Kiali (full service mesh observability)

Kiali provides a visual graph of traffic between services, request rates, error rates,
and Istio configuration validation. It requires Prometheus.

```bash
helm --kube-context minikube-1 upgrade kagenti-deps \
  _sources/kagenti-operator-src/kagenti-operator-main/charts/kagenti-deps \
  -n kagenti-system \
  --reuse-values \
  --set components.kiali.enabled=true \
  --set components.otel.enabled=true \
  --wait --timeout=300s
```

Then open Kiali:

```bash
kubectl --context minikube-1 port-forward \
  -n istio-system svc/kiali 20001:20001

# Open: http://localhost:20001
```

> **RAM requirement:** Kiali + Prometheus adds ~1 GiB. The Podman machine is already at 8 GiB,
> so there is sufficient headroom.

---

## Component status reference

| Component | Namespace | Running | Access method |
|---|---|---|---|
| cert-manager | `cert-manager` | ✅ | — (internal) |
| istiod v1.28.0 | `istio-system` | ✅ | — (internal) |
| Istio Gateway | `kagenti-system` | ✅ | `kubectl port-forward 19080:80` |
| Kagenti Operator | `kagenti-system` | ✅ | — (internal) |
| Kagenti UI | `kagenti-system` | ✅ | `http://kagenti-ui.localtest.me:19080` |
| Kagenti Backend | `kagenti-system` | ✅ | `http://kagenti-api.localtest.me:19080` |
| Keycloak | `keycloak` | ✅ | `http://keycloak.localtest.me:19080` |
| hello-kagenti-agent | `team1` | ✅ | `kubectl port-forward 18000:8000` |
| Kiali | — | ⚠️ Disabled | Enable: `--set components.kiali.enabled=true` |
| Prometheus / OTEL | — | ⚠️ Disabled | Enable: `--set components.otel.enabled=true` |

---

## Quick-start: open everything in one shot

Paste this into a terminal to start all port-forwards at once:

```bash
# Gateway (Kagenti UI + API + Keycloak)
kubectl --context minikube-1 port-forward \
  -n kagenti-system svc/http-istio-np 19080:80 &

# Agent direct access
kubectl --context minikube-1 port-forward \
  -n team1 svc/hello-kagenti-agent 18000:8000 &

echo ""
echo "  Kagenti Dashboard : http://kagenti-ui.localtest.me:19080"
echo "  Kagenti API       : http://kagenti-api.localtest.me:19080/api/v1/agents"
echo "  Keycloak          : http://keycloak.localtest.me:19080"
echo "  Agent health      : http://localhost:18000/health"
echo "  Agent card        : http://localhost:18000/.well-known/agent-card.json"
```

---

## Stopping the application

### Recommended — stop the cluster only (no data loss)

```bash
cd kagenti-hello-agent

./scripts/stop-cluster.sh
```

Stops minikube and the Podman machine, freeing ~8 GiB RAM. All Helm releases,
namespaces, and persistent volumes are preserved on disk.

**Resume later:**

```bash
podman machine start podman-machine-default
minikube start --profile minikube-1 \
  --driver=podman --container-runtime=cri-o --memory=7500 --cpus=4
```

Then restart port-forwards:

```bash
kubectl --context minikube-1 port-forward \
  -n kagenti-system svc/http-istio-np 19080:80 &
kubectl --context minikube-1 port-forward \
  -n team1 svc/hello-kagenti-agent 18000:8000 &
```

### Other stop modes (`stop.sh`)

| Command | Behaviour | Data loss? |
|---|---|---|
| `./scripts/stop.sh` | Pause cluster — same as `stop-cluster.sh` | ❌ None |
| `./scripts/stop.sh --agent-only` | Remove only the agent; platform keeps running | ❌ None |
| `./scripts/stop.sh --destroy` | Delete the cluster entirely (requires `YES` confirmation) | ✅ All |

See `README.md → Stopping / Teardown` for full details.
