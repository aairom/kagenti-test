# Draft Blog Post (Markdown)

## Securing the Agentic Mesh: Building a Local Kagenti Sandbox with Podman, Minikube, and Bob

Until just a few days ago, Kagenti wasn’t even on my radar. That all changed when I stumbled upon an insightful IBM Technology video titled *"Kagenti’s Approach to Multi-Agent Security for AI Agents"*. The video broke down a massive operational hurdle in production AI: the "confused deputy" problem, where a delegated sub-agent can be tricked into abusing its authorization context to leak data or trigger malicious tool calls. Seeing how Kagenti addresses this at the infrastructure layer—using open standards like SPIFFE/SPIRE for cryptographic workload identities and OBridge delegation chains—completely hooked me. I knew right away that I needed to spin up an end-to-end sandbox environment to see it in action on my own hardware.

To bring this architecture to life locally, I mapped out a zero-configuration, lightweight container and Kubernetes stack. My building blocks consisted of **Podman Desktop** and the **Podman Engine** handling the container runtime, **Ollama** running local LLMs to power the autonomous agentic logic, and a combination of **Kind** and **Minikube** to orchestrate the local clusters. Rather than wrestling with the deployment manifests manually, I defined my specific project rules and architectural guidelines, handing them over to my AI development partner, Bob. With the right constraints in place, Bob generated a complete, end-to-end implementation that successfully wired the entire platform together.

Before we dig into the technical nitty-gritty of the deployment manifests and local configurations, let's take a step back and look at what Kagenti actually is, what it does, and why it is rapidly becoming the go-to middleware for enterprise AI engineering.

### What is Kagenti?

**Kagenti** is an open-source, cloud-native middleware platform engineered to deploy, secure, govern, and orchestrate AI agents inside **Kubernetes** environments. While developers have access to numerous frameworks for building AI applications (such as LangGraph, CrewAI, or AG2), there has historically been a significant operational gap in running that agentic code safely in production. Kagenti acts as the framework-neutral infrastructure layer that bridges this gap, turning AI agents into manageable, first-class Kubernetes workloads.

The platform relies strictly on open, industry-converging standards. For communication, it leverages the **Agent-to-Agent (A2A)** protocol, allowing different AI agents to cleanly discover, collaborate, and delegate tasks to one another. For external tool integration, it relies on the **Model Context Protocol (MCP)**, routing all tool calls through an Envoy-backed gateway. To handle enterprise security, Kagenti incorporates a zero-trust model using SPIFFE/SPIRE for workload identities and Keycloak for OAuth2 token validation, preventing data leaks across a chain of delegating agents.

### The Architecture: Mapping Out the Sandbox

Our playground runs inside a dedicated local environment optimized for resources. The underlying infrastructure maps out a clean communication pathway from our local host directly into the cluster:

```
Your Browser
    │
    │  http://kagenti-ui.localtest.me:19080
    ▼
localhost:19080   ←── kubectl port-forward ──►  svc/http-istio-np :80 (kagenti-system)
                                                       │
                                          Istio Gateway (NodePort)
                                                       │
                              ┌─────────────────────────────────────────┐
                              │  HTTPRoute Hostname Matching            │
                              │  kagenti-ui.localtest.me → UI :8080     │
                              │  keycloak.localtest.me   → Keycloak:8080│
                              └─────────────────────────────────────────┘
```

The system is configured via `localtest.me`—a convenient domain that inherently resolves to `127.0.0.1` without forcing messy updates to your local `/etc/hosts` file. A single `kubectl port-forward` targeted at the Istio Ingress Gateway maps all of our services cleanly.

### The Code: Building the `kagenti-hello-agent`

To keep things educational, our sample agent utilizes the official `a2a-sdk` to stand up a simple greeting assistant powered locally by Ollama (`ibm/granite4:3b`).

#### 1. Configuration (`configuration.py`)

We use Pydantic to cleanly bind environment strings to the running application. Notice how we point the `llm_api_base` to `host.docker.internal` so the containerized workload can speak directly back to Ollama running on our host machine.



```python
from pydantic_settings import BaseSettings

class Configuration(BaseSettings):
    """Agent configuration loaded from environment variables."""
    llm_model: str = "ibm/granite4:3b"
    llm_api_base: str = "http://host.docker.internal:11434/v1"
    llm_api_key: str = "dummy"

    host: str = "0.0.0.0"
    port: int = 8000
    agent_endpoint: str = ""
```

#### 2. The LLM Client Wrapper (`llm.py`)

Using the AsyncOpenAI SDK, the core chat loop manages thread state inside memory via a unified `context_id` and tracks logs to make tracing readable.

```python
import logging
from collections import defaultdict
from openai import AsyncOpenAI
from hello_agent.configuration import Configuration

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = (
    "You are a friendly and concise greeting assistant. "
    "Guidelines:\n"
    "- Always start with a personalised greeting.\n"
    "- Be brief: keep every response under 3 sentences.\n"
    "- If asked about your capabilities, explain you are a greeting agent running on Kagenti.\n"
    "- Always end with an encouraging closing.\n"
)

_conversations: dict[str, list[dict[str, str]]] = defaultdict(list)

async def chat(context_id: str, user_message: str) -> str:
    config = Configuration()
    client = AsyncOpenAI(base_url=config.llm_api_base, api_key=config.llm_api_key)

    history = _conversations[context_id]
    history.append({"role": "user", "content": user_message})

    messages = [{"role": "system", "content": SYSTEM_PROMPT}] + history
    response = await client.chat.completions.create(model=config.llm_model, messages=messages)

    reply = response.choices[0].message.content
    history.append({"role": "assistant", "content": reply})
    return reply
```

#### 3. Serving via JSON-RPC over HTTP (`agent.py`)

The A2A protocol works over standard JSON-RPC. We spin up a Starlette web application and hand off routing safely with `enable_v0_3_compat=True` to comply with Kagenti's platform communication needs.

```python
import os
import uvicorn
from starlette.applications import Starlette
from starlette.responses import JSONResponse
from starlette.routing import Route
from a2a.server.routes import create_agent_card_routes, create_jsonrpc_routes

async def health(_: Request) -> JSONResponse:
    return JSONResponse({"status": "ok"})

def run() -> None:
    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", "8000"))
    
    # ... Agent initialization omitted for brevity ...

    routes = [Route("/health", health, methods=["GET"])]
    routes.extend(create_jsonrpc_routes(handler, "/", enable_v0_3_compat=True))

    app = Starlette(routes=routes)
    uvicorn.run(app, host=host, port=port)
```

### Integrating with Kubernetes: The Manifests

How do we hand control of our microservice over to the Kagenti Operator? Through standard Custom Resource Definitions (CRDs). In our `deploy.yaml`, we attach critical platform labels and declare an `AgentRuntime` resource:



```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-kagenti-agent
  namespace: team1
  labels:
    protocol.kagenti.io/a2a: ""
    kagenti.io/framework: "a2a-sdk"
spec:
  template:
    metadata:
      labels:
        kagenti.io/type: agent # Injects the AuthBridge sidecar automatically
    spec:
      containers:
        - name: agent
          image: hello-kagenti-agent:latest
          env:
            - name: LLM_API_BASE
              value: "http://host.docker.internal:11434/v1"
---
apiVersion: agent.kagenti.dev/v1alpha1
kind: AgentRuntime
metadata:
  name: hello-kagenti-agent-runtime
  namespace: team1
spec:
  agentCardRef:
    name: hello-kagenti-agent-card
```

When this `AgentRuntime` resource is applied, the Kagenti Operator triggers a rolling update, registers our target service inside Keycloak, calculates configuration hashes, and hooks our pod cleanly into the zero-trust system without changing a single line of our Python logic.

### Bringing It All Together Locally

Want to fire this up on your machine? The installation lifecycle maps to a quick series of automation steps:



```bash
# 1. Start your podman machine with a proper RAM budget
podman machine start

# 2. Fire up minikube leveraging the podman driver
minikube start --profile minikube-1 --driver=podman --memory=7500 --cpus=4

# 3. Compile and apply your manifests
cd kagenti-hello-agent
./scripts/build-and-deploy.sh

# 4. Open up your connection gateway
kubectl port-forward -n kagenti-system svc/http-istio-np 19080:80 &
```

Once executed, navigate your browser over to `http://kagenti-ui.localtest.me:19080` to log into your brand new dashboard and see Bob's work running natively inside your infrastructure layer. Secure, observable, and fully scalable.

What frameworks are you currently looking to run inside production Kubernetes environments? Let me know down in the comments section below!