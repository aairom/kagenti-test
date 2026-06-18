#!/usr/bin/env bash
# =============================================================================
# setup-cluster.sh
#
# One-shot script to:
#   1. Resize the Podman machine to 8 GiB RAM / 4 CPUs (required for minikube)
#   2. Start the minikube-1 cluster using the Podman driver with CRI-O
#   3. Install cert-manager (required by Kagenti Operator webhooks)
#   4. Install the Kagenti Operator from local Helm chart
#
# Prerequisites:
#   - Podman Desktop installed and the default machine exists
#   - minikube, kubectl, helm installed
#   - Kagenti Operator source at: ../_sources/kagenti-operator-src/kagenti-operator-main/
#   - Kagenti Operator image built locally: localhost/kagenti-operator:v0.2.0-alpha.24
#     (build it with: cd ../_sources/kagenti-operator-src/kagenti-operator-main &&
#                     podman build --platform linux/arm64 -t localhost/kagenti-operator:v0.2.0-alpha.24 .)
#
# Usage:
#   ./scripts/setup-cluster.sh
#   ./scripts/setup-cluster.sh --skip-resize    # skip Podman machine resize
#   ./scripts/setup-cluster.sh --skip-cluster   # skip minikube start
#
# Why port 18000?  macOS reserves 5000 (AirDrop) and 8000 is often in use.
# =============================================================================
set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
PODMAN_MACHINE="podman-machine-default"
PODMAN_MEMORY_MB=8192          # resize target
PODMAN_CPUS=4
MINIKUBE_MEMORY_MB=7500        # slightly under machine limit (libkrun overhead ~300 MB)
MINIKUBE_CPUS=4
MINIKUBE_PROFILE="minikube-1"
CERT_MANAGER_VERSION="v1.16.3"
OPERATOR_IMAGE="localhost/kagenti-operator:v0.2.0-alpha.24"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPERATOR_CHART="${SCRIPT_DIR}/../../_sources/kagenti-operator-src/kagenti-operator-main/charts/kagenti-operator"

SKIP_RESIZE=false
SKIP_CLUSTER=false

for arg in "$@"; do
  case $arg in
    --skip-resize)  SKIP_RESIZE=true  ;;
    --skip-cluster) SKIP_CLUSTER=true ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done

# ── Helpers ───────────────────────────────────────────────────────────────────
log()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()   { echo -e "\033[1;32m[ OK ]\033[0m  $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
step() { echo -e "\n\033[1;35m──── $* ────\033[0m"; }
die()  { echo -e "\033[1;31m[ERR ]\033[0m  $*"; exit 1; }

command -v podman   >/dev/null 2>&1 || die "podman not found"
command -v minikube >/dev/null 2>&1 || die "minikube not found"
command -v kubectl  >/dev/null 2>&1 || die "kubectl not found"
command -v helm     >/dev/null 2>&1 || die "helm not found"

# ── Step 1: Resize Podman machine ─────────────────────────────────────────────
step "Step 1: Podman machine resize"

if [[ "${SKIP_RESIZE}" == "true" ]]; then
  warn "Skipping Podman machine resize (--skip-resize)"
else
  CURRENT_MEM=$(podman machine inspect "${PODMAN_MACHINE}" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0].get('Memory',0))" 2>/dev/null || echo 0)

  if [[ "${CURRENT_MEM}" -ge $((PODMAN_MEMORY_MB * 1024 * 1024)) ]]; then
    ok "Podman machine already has ${CURRENT_MEM} bytes RAM — no resize needed"
  else
    log "Stopping Podman machine '${PODMAN_MACHINE}'…"
    podman machine stop "${PODMAN_MACHINE}" 2>/dev/null || true
    sleep 3

    log "Resizing to ${PODMAN_MEMORY_MB} MiB RAM / ${PODMAN_CPUS} CPUs…"
    podman machine set --memory "${PODMAN_MEMORY_MB}" --cpus "${PODMAN_CPUS}" "${PODMAN_MACHINE}"

    log "Starting Podman machine…"
    podman machine start "${PODMAN_MACHINE}"
    sleep 5
    ok "Podman machine resized and started"
  fi
fi

# Verify available RAM
AVAIL=$(podman machine list --format "{{.CPUs}} {{.Memory}}" 2>/dev/null | head -1 || echo "unknown")
log "Podman machine resources: ${AVAIL}"

# ── Step 2: Start minikube cluster ────────────────────────────────────────────
step "Step 2: minikube cluster"

if [[ "${SKIP_CLUSTER}" == "true" ]]; then
  warn "Skipping minikube start (--skip-cluster)"
elif minikube status --profile "${MINIKUBE_PROFILE}" 2>/dev/null | grep -q "Running"; then
  ok "minikube profile '${MINIKUBE_PROFILE}' is already running"
else
  log "Starting minikube (profile=${MINIKUBE_PROFILE}, memory=${MINIKUBE_MEMORY_MB}MB, cpus=${MINIKUBE_CPUS})…"
  minikube start \
    --profile "${MINIKUBE_PROFILE}" \
    --driver=podman \
    --container-runtime=cri-o \
    --memory="${MINIKUBE_MEMORY_MB}" \
    --cpus="${MINIKUBE_CPUS}"
  ok "minikube started"
fi

log "Waiting for node to be Ready…"
kubectl --context "${MINIKUBE_PROFILE}" wait node/"${MINIKUBE_PROFILE}" \
  --for=condition=Ready --timeout=120s
ok "Node is Ready"

# ── Step 3: Install cert-manager ──────────────────────────────────────────────
step "Step 3: cert-manager ${CERT_MANAGER_VERSION}"

if kubectl --context "${MINIKUBE_PROFILE}" get namespace cert-manager >/dev/null 2>&1; then
  log "cert-manager namespace already exists — checking if ready…"
else
  log "Installing cert-manager ${CERT_MANAGER_VERSION}…"
  kubectl --context "${MINIKUBE_PROFILE}" apply \
    -f "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"
fi

log "Waiting for cert-manager webhook deployment…"
kubectl --context "${MINIKUBE_PROFILE}" -n cert-manager \
  wait deployment/cert-manager-webhook \
  --for=condition=Available --timeout=120s
ok "cert-manager ready"

# ── Step 4: Load operator image into minikube ─────────────────────────────────
step "Step 4: Load Kagenti Operator image into minikube"

if minikube --profile "${MINIKUBE_PROFILE}" image ls 2>/dev/null | grep -q "kagenti-operator"; then
  ok "Operator image already in minikube"
else
  if ! podman image exists "${OPERATOR_IMAGE}"; then
    die "Operator image '${OPERATOR_IMAGE}' not found in Podman.
Build it first:
  cd _sources/kagenti-operator-src/kagenti-operator-main
  podman build --platform linux/arm64 -t ${OPERATOR_IMAGE} ."
  fi

  log "Saving operator image to tar…"
  TMP_TAR="$(mktemp /tmp/kagenti-operator-XXXXXX.tar)"
  trap 'rm -f "${TMP_TAR}"' EXIT
  podman save --output "${TMP_TAR}" "${OPERATOR_IMAGE}"

  log "Loading into minikube…"
  minikube --profile "${MINIKUBE_PROFILE}" image load "${TMP_TAR}"
  ok "Operator image loaded"
fi

# ── Step 5: Install Kagenti Operator ──────────────────────────────────────────
step "Step 5: Kagenti Operator (Helm)"

[[ -f "${OPERATOR_CHART}/Chart.yaml" ]] || \
  die "Helm chart not found at: ${OPERATOR_CHART}
Clone/unzip the operator source first (see README.md)."

if helm --kube-context "${MINIKUBE_PROFILE}" list -n kagenti-system 2>/dev/null | grep -q "kagenti-operator"; then
  log "kagenti-operator release already installed — upgrading…"
  HELM_CMD="upgrade"
else
  HELM_CMD="install"
fi

helm --kube-context "${MINIKUBE_PROFILE}" ${HELM_CMD} kagenti-operator \
  "${OPERATOR_CHART}" \
  --namespace kagenti-system \
  --create-namespace \
  --set controllerManager.container.image.repository=localhost/kagenti-operator \
  --set controllerManager.container.image.tag=v0.2.0-alpha.24 \
  --set controllerManager.container.image.pullPolicy=Never \
  --wait --timeout=120s

ok "Kagenti Operator installed and ready"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅  Kagenti cluster ready!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Context          : ${MINIKUBE_PROFILE}"
echo "  Operator ns      : kagenti-system"
echo "  cert-manager ns  : cert-manager"
echo ""
echo "  Next step: deploy the Hello Agent"
echo "    cd kagenti-hello-agent"
echo "    ./scripts/build-and-deploy.sh"
echo ""
echo "  Or if the agent image is already built:"
echo "    ./scripts/build-and-deploy.sh --skip-build"
echo ""
