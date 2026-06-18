#!/usr/bin/env bash
# =============================================================================
# setup-full-platform.sh  —  Path A
#
# Deploys the full Kagenti platform on a NEW minikube-1 cluster using the
# resized Podman machine (≥8 GB). Installs: Keycloak, Kagenti Operator,
# Kagenti UI, Kagenti backend. Optionally: SPIRE, Istio ambient mesh.
#
# PREREQUISITE: run ./scripts/setup-podman-machine.sh first (machine must
# have ≥8192 MiB). The script will exit early if Podman has < 8192 MiB.
#
# Usage:
#   ./scripts/setup-full-platform.sh [--with-spire] [--with-istio] [--dry-run]
#
# What it does:
#   1. Deletes stale minikube-1 profile (if any)
#   2. Creates new minikube-1 (8192 MB, 4 CPUs, podman driver, cri-o)
#   3. Clones Kagenti repo to /tmp/kagenti (tag v0.7.0-alpha.3)
#   4. Runs setup-kagenti.sh --skip-cluster --with-ui [flags]
#   5. Redeploys the Hello Kagenti Agent
#   6. Prints access URLs
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
KAGENTI_REPO="https://github.com/kagenti/kagenti.git"
KAGENTI_TAG="v0.7.0-alpha.3"
KAGENTI_DIR="/tmp/kagenti"
MINIKUBE_PROFILE="minikube-1"
KUBECTL_CONTEXT="minikube-1"
MINIKUBE_MEMORY=8192
MINIKUBE_CPUS=4
WITH_SPIRE=false
WITH_ISTIO=false
DRY_RUN=false

for arg in "$@"; do
  case $arg in
    --with-spire) WITH_SPIRE=true ;;
    --with-istio) WITH_ISTIO=true ;;
    --dry-run)    DRY_RUN=true    ;;
  esac
done

log()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()   { echo -e "\033[1;32m[ OK ]\033[0m  $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
die()  { echo -e "\033[1;31m[ERR ]\033[0m  $*"; exit 1; }
run()  { $DRY_RUN && echo "[dry-run] $*" || "$@"; }

command -v podman   >/dev/null 2>&1 || die "podman not found"
command -v minikube >/dev/null 2>&1 || die "minikube not found"
command -v kubectl  >/dev/null 2>&1 || die "kubectl not found"
command -v helm     >/dev/null 2>&1 || die "helm not found"
command -v git      >/dev/null 2>&1 || die "git not found"

# ── Check Podman machine RAM ──────────────────────────────────────────────────
PODMAN_MEM=$(podman machine inspect podman-machine-default \
  --format '{{.Resources.Memory}}' 2>/dev/null || echo 0)
if [[ "${PODMAN_MEM}" -lt "${MINIKUBE_MEMORY}" ]]; then
  die "Podman machine has only ${PODMAN_MEM} MiB but ${MINIKUBE_MEMORY} MiB required.
  Run: ./scripts/setup-podman-machine.sh"
fi
ok "Podman machine has ${PODMAN_MEM} MiB RAM — sufficient"

# ── Delete stale profile ──────────────────────────────────────────────────────
log "Removing stale minikube profile '${MINIKUBE_PROFILE}' (if any)..."
run minikube delete --profile "${MINIKUBE_PROFILE}" 2>/dev/null || true
ok "Cleaned up"

# ── Create fresh minikube cluster ─────────────────────────────────────────────
log "Creating minikube-1 (${MINIKUBE_MEMORY} MB, ${MINIKUBE_CPUS} CPUs, cri-o)..."
run minikube start \
  --profile "${MINIKUBE_PROFILE}" \
  --driver=podman \
  --container-runtime=cri-o \
  --memory="${MINIKUBE_MEMORY}" \
  --cpus="${MINIKUBE_CPUS}"
run kubectl config use-context "${KUBECTL_CONTEXT}"
ok "minikube-1 cluster ready"

# ── Clone Kagenti repo ────────────────────────────────────────────────────────
if [[ -d "${KAGENTI_DIR}/.git" ]]; then
  log "Kagenti repo exists — pulling latest..."
  run git -C "${KAGENTI_DIR}" fetch --tags
  run git -C "${KAGENTI_DIR}" checkout "${KAGENTI_TAG}"
else
  log "Cloning Kagenti ${KAGENTI_TAG} to ${KAGENTI_DIR}..."
  run git clone "${KAGENTI_REPO}" "${KAGENTI_DIR}"
  run git -C "${KAGENTI_DIR}" checkout "${KAGENTI_TAG}"
fi
ok "Kagenti repo ready at ${KAGENTI_DIR}"

# ── Build setup-kagenti.sh flags ─────────────────────────────────────────────
SETUP_FLAGS=(
  --skip-cluster
  --with-ui
  --with-backend
)
$WITH_SPIRE && SETUP_FLAGS+=(--with-spire)
$WITH_ISTIO && SETUP_FLAGS+=(--with-istio)
$DRY_RUN    && SETUP_FLAGS+=(--dry-run)

log "Running Kagenti installer: ${SETUP_FLAGS[*]}"
run env CONTAINER_ENGINE=podman \
  bash "${KAGENTI_DIR}/scripts/kind/setup-kagenti.sh" "${SETUP_FLAGS[@]}"
ok "Kagenti platform installed"

# ── Redeploy Hello Kagenti Agent ──────────────────────────────────────────────
log "Rebuilding and deploying Hello Kagenti Agent..."
run "${PROJECT_DIR}/scripts/build-and-deploy.sh"
ok "Hello Kagenti Agent deployed"

# ── Print service URLs ────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Kagenti Platform — Path A (minikube-1) — READY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Start port-forward for UI access:"
echo "    kubectl port-forward svc/kagenti-ui 8080:8080 -n kagenti-system \\"
echo "      --context ${KUBECTL_CONTEXT} &"
echo ""
echo "  Kagenti UI    : http://localhost:8080"
echo "  Keycloak admin: http://localhost:8080/realms/master (via port-forward)"
echo ""
echo "  Get Keycloak admin password:"
echo "    kubectl get secret keycloak-initial-admin -n keycloak \\"
echo "      --context ${KUBECTL_CONTEXT} \\"
echo "      -o jsonpath='{.data.password}' | base64 -d && echo"
echo ""
echo "  Hello Agent (port-forward):"
echo "    kubectl port-forward svc/hello-kagenti-agent 18000:8000 -n team1 \\"
echo "      --context ${KUBECTL_CONTEXT} &"
echo "    curl http://localhost:18000/.well-known/agent-card.json"
echo ""
echo "  All services:"
echo "    bash ${KAGENTI_DIR}/.github/scripts/local-setup/show-services.sh"
echo ""
