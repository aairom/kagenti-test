# Kagenti Test Project

A comprehensive test and development environment for exploring the [Kagenti](https://github.com/kagenti/kagenti) platform — a cloud-native middleware for deploying and orchestrating AI agents through standardized protocols (A2A, MCP).

## Overview

This project provides:
- **Source code repositories** for all Kagenti components
- **Example agent implementation** (`kagenti-hello-agent`)
- **Documentation and guides** for platform setup and agent development
- **Scripts and tools** for local development and testing

## Project Structure

```
kagenti-test/
├── _sources/              # Source code archives and extracted repositories
│   ├── kagenti-main-src/                    # Main Kagenti platform
│   ├── agentic-control-plane-src/           # A2A Control Plane
│   ├── adk-main.zip                         # Agent Development Kit
│   ├── agent-examples-main.zip              # Agent examples
│   ├── kagenti-operator-main.zip            # Kubernetes operator
│   └── keycloak-*/                          # Keycloak integration
├── _images/               # Project images and screenshots
├── _output/               # Generated output documents
├── _tmp/                  # Temporary files
├── kagenti-hello-agent/   # Example A2A agent implementation
├── Docs/                  # Project documentation (if any)
└── README.md              # This file
```

## Kagenti Ecosystem

### Core Components

| Component | Repository | Description |
|-----------|------------|-------------|
| **Kagenti Platform** | [kagenti/kagenti](https://github.com/kagenti/kagenti) | Main platform with UI, backend, and core services |
| **Agent Development Kit (ADK)** | [kagenti/adk](https://github.com/kagenti/adk) | SDK for building Kagenti-compatible agents |
| **Kagenti Operator** | [kagenti/kagenti-operator](https://github.com/kagenti/kagenti-operator) | Kubernetes operator for agent lifecycle management |
| **A2A Control Plane** | [kagenti/agentic-control-plane](https://github.com/kagenti/agentic-control-plane) | Agent-to-Agent communication control plane |
| **Agent Examples** | [kagenti/agent-examples](https://github.com/kagenti/agent-examples) | Reference implementations and examples |

### Additional Resources

- **MCP Gateway**: [Kuadrant/mcp-gateway](https://github.com/Kuadrant/mcp-gateway) — Unified gateway for Model Context Protocol servers
- **Plugins Adapter**: [kagenti/plugins-adapter](https://github.com/kagenti/plugins-adapter) — Security and safety plugins for Envoy-based gateways
- **Kagenti Extensions**: [kagenti/kagenti-extensions](https://github.com/kagenti/kagenti-extensions) — Additional components and demos

## Supported Protocols

- **[A2A (Agent-to-Agent)](https://a2a-protocol.org/latest/)** — Standard protocol for agent communication
- **[MCP (Model Context Protocol)](https://modelcontextprotocol.io)** — Protocol for tool/server integration

## Example Agent: kagenti-hello-agent

A minimal A2A greeting agent demonstrating:
- JSON-RPC endpoint compliant with the Google A2A protocol
- Integration with Ollama LLM (`ibm/granite4:3b`)
- Automatic discovery by Kagenti Operator via `AgentRuntime` CR
- Visibility in the Kagenti Agents Dashboard

See [kagenti-hello-agent/README.md](kagenti-hello-agent/README.md) for full documentation.

## Quick Start

### Prerequisites

- Python ≥ 3.11 with [uv](https://docs.astral.sh/uv/getting-started/installation)
- Docker Desktop, Rancher Desktop, or Podman (16GB RAM, 4 cores recommended)
- [Kind](https://kind.sigs.k8s.io) or [minikube](https://minikube.sigs.k8s.io/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/)
- [Ollama](https://ollama.com/download) for local LLM inference

### Setup

1. **Clone the Kagenti repository**:
   ```bash
   git clone https://github.com/kagenti/kagenti.git
   cd kagenti
   git checkout v0.6.0
   ```

2. **Deploy to Kind cluster**:
   ```bash
   scripts/kind/setup-kagenti.sh --with-ui --with-spire --with-agent-sandbox --with-builds
   ```

3. **Access the UI**:
   ```bash
   .github/scripts/local-setup/show-services.sh
   open http://kagenti-ui.localtest.me:8080
   ```

For detailed instructions, see the [Kagenti Installation Guide](https://github.com/kagenti/kagenti/blob/main/docs/install.md).

## Documentation

### Kagenti Platform Documentation

| Topic | Link |
|-------|------|
| **Installation** | [Installation Guide](https://github.com/kagenti/kagenti/blob/main/docs/install.md) |
| **Components** | [Component Details](https://github.com/kagenti/kagenti/blob/main/docs/components.md) |
| **Demos & Tutorials** | [Demo Documentation](https://github.com/kagenti/kagenti/blob/main/docs/demos/README.md) |
| **Developing Apps** | [Application Development Guide](https://github.com/kagenti/kagenti/blob/main/docs/developing-kagenti-app.md) |
| **Import Your Agent** | [New Agent Guide](https://github.com/kagenti/kagenti/blob/main/docs/new-agent.md) |
| **Import Your Tool** | [New Tool Guide](https://github.com/kagenti/kagenti/blob/main/docs/new-tool.md) |
| **Skills Guide** | [Skills Configuration](https://github.com/kagenti/kagenti/blob/main/docs/skills.md) |
| **Architecture** | [Technical Details](https://github.com/kagenti/kagenti/blob/main/docs/tech-details.md) |
| **Identity & Auth** | [Identity Guide](https://github.com/kagenti/kagenti/blob/main/docs/identity-guide.md) |
| **Developer Guide** | [Contributing](https://github.com/kagenti/kagenti/blob/main/CONTRIBUTING.md) |
| **Troubleshooting** | [Troubleshooting Guide](https://github.com/kagenti/kagenti/blob/main/docs/troubleshooting.md) |

### Local Project Documentation

- [kagenti-hello-agent/README.md](kagenti-hello-agent/README.md) — Example agent implementation
- [kagenti-hello-agent/Docs/Architecture.md](kagenti-hello-agent/Docs/Architecture.md) — Architecture diagrams
- [kagenti-hello-agent/Docs/AccessGuide.md](kagenti-hello-agent/Docs/AccessGuide.md) — Access and observability guide
- [kagenti-hello-agent/Docs/Platform-Setup.md](kagenti-hello-agent/Docs/Platform-Setup.md) — Platform setup guide

## Architecture

Kagenti provides a pluggable agentic platform blueprint organized into four key pillars:

1. **Lifecycle Orchestration** — Agent/tool lifecycle, discovery, container builds
2. **Networking** — Tool routing, service mesh, ingress/routing
3. **Security** — Identity & auth, OAuth/OIDC, workload identity (SPIFFE/SPIRE)
4. **Observability** — Tracing, network visualization

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                         KAGENTI PLATFORM                                │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                  KAGENTI UI + Backend API                               │
│                                                 │                                       │
│                                                 ▼                                       │
│  ┌───────────────────────────────────────────────────────────────────────────────────┐  │
│  │                                    WORKLOAD RUNTIME                               │  │
│  │   ┌──────────────────────┐    ┌──────────────────────┐    ┌───────────────────┐   │  │
│  │   │       AGENTS         │    │        TOOLS         │    │      SKILLS       │   │  │
│  │   │  (A2A Protocol)      │    │  (MCP Protocol)      │    │   (Reusable)      │   │  │
│  │   └──────────────────────┘    └──────────────────────┘    └───────────────────┘   │  │
│  └───────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                         │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐  ┌────────────────┐   │
│  │    LIFECYCLE     │  │    NETWORKING    │  │     SECURITY     │  │  OBSERVABILITY │   │
│  │  ORCHESTRATION   │  │                  │  │                  │  │                │   │
│  └──────────────────┘  └──────────────────┘  └──────────────────┘  └────────────────┘   │
│                                                                                         │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                 KUBERNETES / OPENSHIFT                                  │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

## Contributing

We welcome contributions! See the [Kagenti Contributing Guide](https://github.com/kagenti/kagenti/blob/main/CONTRIBUTING.md) for guidelines.

## Community

- **Slack**: [Join us on Slack](https://ibm.biz/kagenti-slack)
- **Email**: kagenti-maintainers@googlegroups.com
- **Website**: [kagenti.io](http://kagenti.io)

## License

This project and all Kagenti components are licensed under the **Apache License 2.0**.

```
Copyright 2024-2026 Kagenti Contributors

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```

See the full license text:
- [Apache License 2.0](http://www.apache.org/licenses/LICENSE-2.0)
- [Kagenti LICENSE](https://github.com/kagenti/kagenti/blob/main/LICENSE)
- [A2A Control Plane LICENSE](https://github.com/kagenti/agentic-control-plane/blob/main/LICENSE)

## Badges

[![CI](https://github.com/kagenti/kagenti/actions/workflows/ci.yaml/badge.svg)](https://github.com/kagenti/kagenti/actions/workflows/ci.yaml)
[![E2E K8s 1.35.0 (Kind)](https://github.com/kagenti/kagenti/actions/workflows/e2e-kind.yaml/badge.svg)](https://github.com/kagenti/kagenti/actions/workflows/e2e-kind.yaml)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/kagenti/kagenti/badge)](https://scorecard.dev/viewer/?uri=github.com/kagenti/kagenti)
[![GitHub Release](https://img.shields.io/github/v/release/kagenti/kagenti)](https://github.com/kagenti/kagenti/releases/latest)
[![License](https://img.shields.io/github/license/kagenti/kagenti)](https://github.com/kagenti/kagenti/blob/main/LICENSE)
[![Slack](https://img.shields.io/badge/Slack-Join%20us-4A154B?logo=slack&logoColor=white)](https://ibm.biz/kagenti-slack)

---

**Note**: This is a test/development project. For production deployments, refer to the official [Kagenti documentation](https://github.com/kagenti/kagenti).