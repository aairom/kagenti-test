# Architecture — Hello Kagenti Agent

## Overview

This project implements a minimal **A2A (Agent-to-Agent) greeting agent** deployed on the full
**Kagenti platform stack** running locally on minikube.

The full stack runs locally:
- **macOS host** — Podman Desktop (builds + runs the libkrun VM), Ollama (LLM at `:11434`)
- **minikube-1** (Podman driver, CRI-O, Kubernetes v1.35.1) — full Kagenti platform + agent workload

### Deployed Helm releases

| Release | Chart | Version | Namespace |
|---|---|---|---|
| `istio-base` | `base` | 1.28.0 | `istio-system` |
| `istiod` | `istiod` | 1.28.0 | `istio-system` |
| `kagenti-deps` | `kagenti-deps` | 0.1.0 | `kagenti-system` |
| `kagenti` | `kagenti` | 0.7.0-alpha.2 | `kagenti-system` |

The Kagenti Operator is **embedded inside the `kagenti` Helm release** (not a separate install when
using the full platform chart). The standalone operator install (used in `setup-cluster.sh`) is only
needed when running without the full platform.

---

## High-Level Architecture

```mermaid
flowchart TB
    subgraph Host["Host Machine (macOS arm64  36 GB RAM)"]
        Podman["Podman Desktop\nlibkrun VM  8 GiB / 4 CPUs"]
        Ollama["Ollama :11434\nibm/granite4:3b"]
        Dev["Developer\n(kubectl / scripts)"]
        Browser["Browser"]
    end

    subgraph Minikube["minikube-1  Kubernetes v1.35.1  (Podman driver · CRI-O · 7500 MB)"]
        subgraph CertManager["cert-manager"]
            CM["cert-manager v1.16.3"]
        end
        subgraph IstioNS["istio-system"]
            Istiod["istiod v1.28.0"]
            GW["Istio Gateway\nhttp-istio-np  NodePort:30080"]
        end
        subgraph KagentiSystem["kagenti-system"]
            Op["Kagenti Operator v0.2.0-alpha.24\n(embedded in kagenti chart)"]
            UI["Kagenti UI v0.7.0-alpha.3\n:8080"]
            BE["Kagenti Backend v0.7.0-alpha.3\n:8000"]
        end
        subgraph KeycloakNS["keycloak"]
            KC["Keycloak :8080  + Postgres"]
        end
        subgraph NS["team1"]
            Agent["hello-kagenti-agent\n:8000  A2A JSON-RPC"]
            Svc["Service ClusterIP :8000"]
            AR["AgentRuntime CR"]
            AC["AgentCard CR  Synced=True"]
        end
    end

    Dev -- "scripts/build-and-deploy.sh" --> Agent
    Dev -- "kubectl port-forward 18000:8000" --> Svc --> Agent
    Dev -- "kubectl port-forward 19080:80" --> GW
    Browser -- "kagenti-ui.localtest.me:19080" --> GW --> UI
    Browser -- "kagenti-api.localtest.me:19080" --> GW --> BE
    Browser -- "keycloak.localtest.me:19080" --> GW --> KC
    Podman -- "podman save | minikube image load" --> Agent

    CM -- "webhook TLS certs" --> Op
    AR -- "reconcile" --> Op
    Op -- "fetches /.well-known/agent-card.json\ncreates AgentCard CR" --> AC
    Op -- "labels pods kagenti.io/type:agent" --> Agent
    Agent -- "POST /v1/chat/completions\nhost.docker.internal:11434" --> Ollama
```

---

## Component Diagram

```mermaid
classDiagram
    class HelloAgent {
        +get_agent_card(host, port) AgentCard
        +run() void
        -routes: List~Route~
    }

    class HelloExecutor {
        +execute(context, event_queue) void
        +cancel(context, event_queue) void
    }

    class LLM {
        +chat(context_id, user_message) str
        -_conversations: dict~str, list~
        -SYSTEM_PROMPT: str
    }

    class Configuration {
        +llm_model: str = "ibm/granite4:3b"
        +llm_api_base: str = "http://host.docker.internal:11434/v1"
        +llm_api_key: str = "dummy"
        +host: str = "0.0.0.0"
        +port: int = 8000
        +agent_endpoint: str = ""
    }

    HelloAgent --> HelloExecutor
    HelloExecutor --> LLM
    LLM --> Configuration
    HelloAgent --> Configuration
```

---

## Request Flow

```mermaid
sequenceDiagram
    participant Client as A2A Client
    participant Agent as Hello Kagenti Agent\n(port 8000)
    participant LLM as Ollama (ibm/granite4:3b)\n(host:11434)

    Client->>Agent: POST / (JSON-RPC message/send)
    Agent->>Agent: Parse user message
    Agent-->>Client: Status: WORKING ("Thinking of the best way to say hello…")
    Agent->>LLM: POST /v1/chat/completions
    LLM-->>Agent: assistant reply
    Agent-->>Client: Artifact (text reply)
    Agent-->>Client: Status: INPUT_REQUIRED (awaiting next message)
```

---

## Kagenti Operator Integration

```mermaid
flowchart LR
    subgraph K8s["Kubernetes (minikube-1)"]
        Deploy["Deployment\nlabel: protocol.kagenti.io/a2a"]
        AR["AgentRuntime CR\ntargetRef → Deployment\ntype: agent"]
        Op["Kagenti Operator\nkagenti-system ns\nfeatureGates.globalEnabled=false"]
        AC["AgentCard\nhello-kagenti-agent-deployment-card\nSynced=True"]
        CM["cert-manager\n(TLS prerequisite)"]
        FG["kagenti-feature-gates ConfigMap"]
    end

    CM -- "issues webhook cert" --> Op
    FG -- "globalEnabled: false\n(AuthBridge/SPIRE injection off)" --> Op
    AR -- "reconcile" --> Op
    Op -- "applies labels\nkagenti.io/type: agent" --> Deploy
    Op -- "fetches /.well-known/agent-card.json\ncreates AgentCard CR" --> AC
    AC -- "protocol: a2a\nsynced: true" --> UI["Kagenti UI\nAgents Dashboard"]
```

> **`globalEnabled: false`** — The Kagenti AuthBridge sidecar injection (SPIRE + Envoy proxy) is
> disabled. This is required when running without a full SPIRE deployment. The agent pod runs as a
> single container with no sidecar. To re-enable: patch the `kagenti-feature-gates` ConfigMap in
> `kagenti-system` and set `globalEnabled: true` — but only after deploying SPIRE.

### Kagenti Operator — Install Notes

The operator image (`ghcr.io/kagenti/kagenti-operator`) is **private**. It must be built from source:

```bash
# Build from source (arm64 macOS)
cd _sources/kagenti-operator-src/kagenti-operator-main
podman build --platform linux/arm64 \
  -t localhost/kagenti-operator:v0.2.0-alpha.24 -f Dockerfile .

# Load into minikube via tar (minikube image load requires a tar on Podman)
podman save localhost/kagenti-operator:v0.2.0-alpha.24 -o /tmp/op.tar
minikube image load /tmp/op.tar --profile minikube-1

# Install via Helm (values.yaml image path: controllerManager.container.image)
cd kagenti-hello-agent
helm install kagenti-operator \
  ../_sources/kagenti-operator-src/kagenti-operator-main/charts/kagenti-operator \
  --namespace kagenti-system --create-namespace \
  --kube-context minikube-1 \
  --set controllerManager.container.image.repository=localhost/kagenti-operator \
  --set controllerManager.container.image.tag=v0.2.0-alpha.24 \
  --set controllerManager.container.image.pullPolicy=Never \
  --wait --timeout=120s
```

> **Note (Podman + minikube):** `minikube image load <image-name>` fails when using the Podman driver
> because minikube cannot reach the Podman socket directly. Always save to a `.tar` file first and
> load the tar — this is what all scripts in this project do.

### Key Labels Applied by the Operator

| Label | Value | Purpose |
|---|---|---|
| `protocol.kagenti.io/a2a` | `""` | Marks this workload as an A2A-speaking agent |
| `kagenti.io/type` | `agent` | Triggers AuthBridge sidecar injection (if SPIRE enabled) |
| `app.kubernetes.io/managed-by` | `kagenti-operator` | Ownership tracking on AgentCard |

### AgentRuntime Status (observed)

| Condition | Status | Reason |
|---|---|---|
| `TargetResolved` | `True` | Deployment `hello-kagenti-agent` found |
| `ConfigResolved` | `True` | Configuration resolved successfully |
| `Ready` / `Phase` | `True` / `Active` | Workload configured with config-hash |
| AgentCard `Synced` | `True` | Operator fetched agent card successfully |
| AuthBridge injection | Disabled | `globalEnabled: false` in feature-gates ConfigMap |

---

## Observability

### Current state

| Tool | Status | Notes |
|---|---|---|
| Istio service mesh (istiod) | ✅ Running | Traffic metrics available once Kiali enabled |
| Kiali | ⚠️ Disabled | `components.kiali.enabled: false` in `kagenti-deps` |
| Prometheus / OTEL | ⚠️ Disabled | `components.otel.enabled: false` in `kagenti-deps` |

### Network routing — how `localtest.me` works

All UIs route through a **single Istio gateway** (`http-istio-np`, NodePort 30080).
`localtest.me` always resolves to `127.0.0.1` — which maps to `localhost:19080` via port-forward.

```
Browser  →  localhost:19080  →  kubectl port-forward  →  http-istio-np:80
                                                              ↓
                              Host: kagenti-ui.localtest.me → kagenti-ui:8080
                              Host: kagenti-api.localtest.me → kagenti-backend:8000
                              Host: keycloak.localtest.me    → keycloak-service:8080
```

The minikube node IP (`192.168.49.2`) is **not reachable** from macOS when using the Podman driver —
port-forward is the only access method.

### Enable Kiali

```bash
helm --kube-context minikube-1 upgrade kagenti-deps \
  _sources/kagenti-operator-src/kagenti-operator-main/charts/kagenti-deps \
  -n kagenti-system \
  --reuse-values \
  --set components.kiali.enabled=true \
  --set components.otel.enabled=true \
  --wait --timeout=300s

# Then access Kiali:
kubectl --context minikube-1 port-forward \
  -n istio-system svc/kiali 20001:20001
# http://localhost:20001
```

---

## File Structure

```
kagenti-hello-agent/
├── src/
│   └── hello_agent/
│       ├── __init__.py         # Package init
│       ├── agent.py            # A2A server entry point (AgentCard + routes + executor)
│       ├── llm.py              # Async OpenAI-compat LLM client + conversation memory
│       └── configuration.py   # Pydantic settings (env vars)
├── k8s/
│   └── deploy.yaml             # Namespace + Deployment + Service + AgentRuntime CR
├── scripts/
│   ├── setup-cluster.sh       # Resize Podman machine + start minikube + cert-manager + operator
│   ├── build-and-deploy.sh    # Build image → load into minikube → kubectl apply
│   ├── test-agent.sh          # Port-forward → health + AgentCard + JSON-RPC smoke tests
│   └── teardown.sh            # kubectl delete cleanup
├── Docs/
│   ├── Architecture.md        # This file — full Mermaid diagrams, platform stack
│   └── AccessGuide.md         # All port-forward commands, UIs, and observability options
├── Dockerfile                 # uv/Python 3.12 bookworm-slim, non-root UID 1001
├── pyproject.toml             # Python project + a2a-sdk>=1.1.0 + openai>=2.41 deps
└── .gitignore
```

---

## Environment Variables

| Variable | Default | Source |
|---|---|---|
| `LLM_MODEL` | `ibm/granite4:3b` | `k8s/deploy.yaml` env |
| `LLM_API_BASE` | `http://host.docker.internal:11434/v1` | `k8s/deploy.yaml` env |
| `LLM_API_KEY` | `dummy` | `k8s/deploy.yaml` env |
| `HOST` | `0.0.0.0` | `k8s/deploy.yaml` env |
| `PORT` | `8000` | `k8s/deploy.yaml` env |
| `AGENT_ENDPOINT` | *(empty — auto)* | `k8s/deploy.yaml` env |

> `host.docker.internal` resolves to the Mac host IP (`192.168.127.254`) inside minikube via Podman Desktop's `gvproxy` — no extra host networking configuration required.
