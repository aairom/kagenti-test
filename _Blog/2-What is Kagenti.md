

## What is Kagenti?

**Kagenti** (also evolving under the name *Rosso*) is an open-source, cloud-native middleware platform specifically engineered to deploy, secure, govern, and orchestrate AI agents inside **Kubernetes** environments. While developers have access to numerous frameworks for building AI applications (such as LangGraph, CrewAI, or AG2), there has historically been a significant operational gap in running that agentic code in production. Kagenti acts as the framework-neutral infrastructure layer that bridges this gap, turning AI agents into manageable, first-class Kubernetes workloads.

The platform relies strictly on open, industry-converging standards. For communication, it leverages the **Agent-to-Agent (A2A)** protocol, allowing different AI agents to cleanly discover, collaborate, and delegate tasks to one another. For external tool integration, it relies on the **Model Context Protocol (MCP)**, routing all tool calls (like interacting with databases, GitHub, or internal APIs) through an Envoy-backed **MCP Gateway**. To handle enterprise security, Kagenti incorporates a zero-trust model using SPIRE for workload identities and Keycloak for OAuth2 token validation, preventing common multi-agent security vulnerabilities like the "confused deputy" problem, where data permissions can accidentally leak along a chain of delegating agents.

## How Kagenti is Used

Kagenti is used by treating AI agents and their tools exactly like traditional containerized microservices. Instead of learning a entirely new, proprietary AI dashboard, platform engineers manage the lifecycle of an agent declaratively using Kubernetes **Custom Resource Definitions (CRDs)**. This means agents can be versioned in Git, rolled out via standard CI/CD and GitOps workflows, and managed via command-line utilities using `kubectl`.

Operationally, the platform provides an **Agent Development Kit (ADK)** in both Python and Go to wrap existing agent logic without forcing developers to rewrite their code. When deployed, the Kagenti platform automatically injects critical runtime sidecars and shared services, including built-in LLM proxies (abstracting 15+ model providers), session memory backed by PostgreSQL, vector search capabilities via `pgvector`, and end-to-end tracing powered by OpenTelemetry and Phoenix. Administrators can monitor real-time execution steps, track token budgets, and view interaction histories directly from the Kagenti UI.

## Enterprise Use Cases

Because it introduces robust auditing, RBAC (Role-Based Access Control), and network isolation, Kagenti is primarily utilized to bring autonomous AI into enterprise and platform engineering operations:

- **Automated Incident Response:** Running a pager-aware agent that wakes up when an alert fires, autonomously triages system metrics, navigates OpenTelemetry traces, drafts a runbook, and opens a rollback PR—all while utilizing Kagenti's Human-in-the-Loop (HITL) gates to wait for an engineer's manual approval before executing a fix.
- **Platform Self-Service & GitOps:** Enabling developers to request cloud architecture resources (like a new database or an isolated testing namespace) using plain text. The self-service agent checks resource constraints, verifies permissions, and dynamically generates the required infrastructure-as-code pull requests.
- **Observability Copilots:** Interfacing directly with internal monitoring stacks. Engineers can ask an agent complex troubleshooting questions, such as *"Why did our checkout service p99 latency spike at 3:00 AM?"* The agent interrogates the system and yields an answer complete with logs and citation links.
- **Secure Knowledge Services:** Executing Retrieval-Augmented Generation (RAG) across sensitive internal documents, Slack history, and architectural records. Kagenti ensures the agent strictly respects enterprise data boundaries and leaves an unalterable audit trail of which files were accessed.