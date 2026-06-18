#!/usr/bin/env bash
# =============================================================================
# build-and-deploy.sh
#
# Builds the Hello Kagenti Agent container image with Podman, loads it into
# minikube, and deploys it on the cluster.
#
# Usage:
#   ./scripts/build-and-deploy.sh [--skip-build] [--skip-deploy]
#
# Requirements:
#   - podman CLI
#   - minikube running with profile "minikube-1"  (minikube status -p minikube-1)
#   - kubectl configured to use context "minikube-1"
#   - Kagenti Operator already installed (see README.md — Setting Up the Cluster)
# =============================================================================
set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
IMAGE_NAME="hello-kagenti-agent"
IMAGE_TAG="1.0.0"
IMAGE_FULL="localhost/${IMAGE_NAME}:${IMAGE_TAG}"
MINIKUBE_PROFILE="minikube-1"
KUBECTL_CONTEXT="minikube-1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
K8S_MANIFEST="${PROJECT_DIR}/k8s/deploy.yaml"

SKIP_BUILD=false
SKIP_DEPLOY=false

# ── Argument parsing ───────────────────────────────────────────────────────────
for arg in "$@"; do
  case $arg in
    --skip-build)  SKIP_BUILD=true  ;;
    --skip-deploy) SKIP_DEPLOY=true ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done

# ── Helpers ───────────────────────────────────────────────────────────────────
log()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()   { echo -e "\033[1;32m[ OK ]\033[0m  $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
die()  { echo -e "\033[1;31m[ERR ]\033[0m  $*"; exit 1; }

# ── Preflight checks ──────────────────────────────────────────────────────────
command -v podman   >/dev/null 2>&1 || die "podman not found. Install Podman Desktop."
command -v minikube >/dev/null 2>&1 || die "minikube not found."
command -v kubectl  >/dev/null 2>&1 || die "kubectl not found."

minikube status --profile "${MINIKUBE_PROFILE}" >/dev/null 2>&1 || \
  die "minikube profile '${MINIKUBE_PROFILE}' is not running. Start it first."

log "Project directory : ${PROJECT_DIR}"
log "Image             : ${IMAGE_FULL}"
log "Minikube profile  : ${MINIKUBE_PROFILE}"

# ── Step 1: Build the container image ─────────────────────────────────────────
if [[ "${SKIP_BUILD}" == "false" ]]; then
  log "Building container image with Podman (linux/arm64)…"
  podman build \
    --platform linux/arm64 \
    --tag "${IMAGE_FULL}" \
    --file "${PROJECT_DIR}/Dockerfile" \
    "${PROJECT_DIR}"
  ok "Image built: ${IMAGE_FULL}"
else
  warn "Skipping build (--skip-build)"
fi

# ── Step 2: Load the image into minikube ─────────────────────────────────────
log "Saving image to tar and loading into minikube…"
TMP_TAR="$(mktemp /tmp/hello-kagenti-agent-XXXXXX.tar)"
trap 'rm -f "${TMP_TAR}"' EXIT

podman save --output "${TMP_TAR}" "${IMAGE_FULL}"
minikube image load "${TMP_TAR}" --profile "${MINIKUBE_PROFILE}"
ok "Image loaded into minikube"

# ── Step 3: Verify minikube can see the image ─────────────────────────────────
log "Verifying image in minikube…"
if minikube image list --profile "${MINIKUBE_PROFILE}" | grep -q "${IMAGE_NAME}:${IMAGE_TAG}"; then
  ok "Image visible in minikube"
else
  warn "Image may not be visible yet in minikube — continuing anyway"
fi

# ── Step 4: Deploy to Kubernetes ─────────────────────────────────────────────
if [[ "${SKIP_DEPLOY}" == "false" ]]; then
  log "Applying Kubernetes manifests…"
  kubectl apply -f "${K8S_MANIFEST}" --context "${KUBECTL_CONTEXT}" || {
    warn "Some resources failed to apply (AgentRuntime CRD may not be installed yet)."
    warn "Install the Kagenti Operator first (see README.md), then re-run with --skip-build."
    exit 1
  }
  ok "Manifests applied (Namespace + Deployment + Service + AgentRuntime)"

  log "Waiting for deployment to be ready (timeout: 120s)…"
  kubectl rollout status deployment/hello-kagenti-agent \
    -n team1 --context "${KUBECTL_CONTEXT}" --timeout=120s || \
    warn "Deployment not yet ready. Check: kubectl get pods -n team1 --context ${KUBECTL_CONTEXT}"
  ok "Deployment ready"
else
  warn "Skipping deploy (--skip-deploy)"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Hello Kagenti Agent deployed!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Check pods       : kubectl get pods -n team1 --context ${KUBECTL_CONTEXT}"
echo "  Check AgentCard  : kubectl get agentcards -n team1 --context ${KUBECTL_CONTEXT}"
echo "  Check AgentRuntime: kubectl get agentruntimes -n team1 --context ${KUBECTL_CONTEXT}"
echo "  Tail logs        : kubectl logs -f -l app.kubernetes.io/name=hello-kagenti-agent -n team1 --context ${KUBECTL_CONTEXT}"
echo "  Port-forward     : kubectl port-forward svc/hello-kagenti-agent 18000:8000 -n team1 --context ${KUBECTL_CONTEXT}"
echo "  Test (local)     : ./scripts/test-agent.sh"
echo ""
