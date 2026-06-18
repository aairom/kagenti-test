#!/usr/bin/env bash
# =============================================================================
# setup-kind-platform.sh  —  Path B
#
# Deploys the full Kagenti platform on a dedicated Kind cluster named "kagenti".
# Kind is the fully-supported upstream path documented in the Kagenti repo.
#
# PREREQUISITE: run ./scripts/setup-podman-machine.sh first (machine must
# have ≥8192 MiB). The script will exit early if Podman has < 8192 MiB.
#
# Usage:
#   ./scripts/setup-kind-platform.sh [--with-spire] [--with-istio] [--with-all] [--dry-run]
#
# What it does:
#   1. Clones Kagenti repo to /tmp/kagenti (tag v0.7.0-alpha.3)
#   2. Runs setup-kagenti.sh (creates Kind cluster "kagenti" with NodePort 30080→8080)
#   3. Loads the Hello Kagenti Agent image into the Kind cluster
#   4. Deploys the Hello Kagenti Agent
#   5. Prints access URLs
#
# Access URLs use localtest.me (always resolves to 127.0.0.1 — no /etc/hosts needed):
#   Kagenti UI  : http://kagenti-ui.localtest.me:8080
#   Keycloak    : http://keycloak.localtest.me:8080
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
KAGENTI_REPO="https://github.com/kagenti/kagenti.git"
KAGENTI_TAG="v0.7.0-alpha.3"
KAGENTI_DIR="/tmp/kagenti"
KIND_CLUSTER="kagenti"
KUBECTL_CONTEXT="kind-${KIND_CLUSTER}"
WITH_SPIRE=false
WITH_ISTIO=false
WITH_ALL=false
DRY_RUN=false

for arg in "$@"; do
  case $arg in
    --with-spire) WITH_SPIRE=true ;;
    --with-istio) WITH_ISTIO=true ;;
    --with-all)   WITH_ALL=true   ;;
    --dry-run)    DRY_RUN=true    ;;
  esac
done

log()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()   { echo -e "\033[1;32m[ OK ]\033[0m  $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
die()  { echo -e "\033[1;31m[ERR ]\033[0m  $*"; exit 1; }
run()  { $DRY_RUN && echo "[dry-run] $*" || "$@"; }

command -v kind    >/dev/null 2>&1 || die "kind not found. Install: brew install kind"
command -v podman  >/dev/null 2>&1 || die "podman not found"
command -v kubectl >/dev/null 2>&1 || die "kubectl not found"
command -v helm    >/dev/null 2>&1 || die "helm not found"
command -v git     >/dev/null 2>&1 || die "git not found"

# ── Check Podman machine RAM ──────────────────────────────────────────────────
PODMAN_MEM=$(podman machine inspect podman-machine-default \
  --format '{{.Resources.Memory}}' 2>/dev/null || echo 0)
if [[ "${PODMAN_MEM}" -lt 8192 ]]; then
  die "Podman machine has only ${PODMAN_MEM} MiB but ≥8192 MiB required.
  Run: ./scripts/setup-podman-machine.sh"
fi
ok "Podman machine has ${PODMAN_MEM} MiB RAM — sufficient"

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
  --with-ui
  --with-backend
)
if $WITH_ALL; then
  SETUP_FLAGS=(--with-all)
else
  $WITH_SPIRE && SETUP_FLAGS+=(--with-spire)
  $WITH_ISTIO && SETUP_FLAGS+=(--with-istio)
fi
$DRY_RUN && SETUP_FLAGS+=(--dry-run)

log "Running Kagenti installer (Kind): ${SETUP_FLAGS[*]}"
run env CONTAINER_ENGINE=podman \
  bash "${KAGENTI_DIR}/scripts/kind/setup-kagenti.sh" "${SETUP_FLAGS[@]}"
ok "Kagenti platform installed on Kind cluster '${KIND_CLUSTER}'"

# ── Build and load Hello Kagenti Agent into Kind ─────────────────────────────
IMAGE_FULL="localhost/hello-kagenti-agent:1.0.0"
TMP_TAR="/tmp/hello-kagenti-agent-kind.tar"

log "Building Hello Kagenti Agent image (linux/arm64)..."
run podman build \
  --platform linux/arm64 \
  -t "${IMAGE_FULL}" \
  -f "${PROJECT_DIR}/Dockerfile" \
  "${PROJECT_DIR}"
ok "Image built: ${IMAGE_FULL}"

log "Saving image and loading into Kind cluster '${KIND_CLUSTER}'..."
run podman save "${IMAGE_FULL}" -o "${TMP_TAR}"
run kind load image-archive "${TMP_TAR}" --name "${KIND_CLUSTER}"
rm -f "${TMP_TAR}"
ok "Image loaded into Kind"

# ── Deploy Hello Kagenti Agent ────────────────────────────────────────────────
log "Deploying Hello Kagenti Agent to Kind cluster..."
run kubectl apply -f "${PROJECT_DIR}/k8s/deploy.yaml" --context "${KUBECTL_CONTEXT}"
run kubectl rollout status deployment/hello-kagenti-agent \
  -n team1 --context "${KUBECTL_CONTEXT}" --timeout=120s
ok "Hello Kagenti Agent deployed"

# ── Print service URLs ────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Kagenti Platform — Path B (Kind cluster '${KIND_CLUSTER}') — READY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  localtest.me resolves to 127.0.0.1 — no /etc/hosts changes needed."
echo "  Kind NodePort 30080 → host:8080 is configured in the Kind cluster spec."
echo ""
echo "  Kagenti UI    : http://kagenti-ui.localtest.me:8080"
echo "  Kagenti API   : http://kagenti-api.localtest.me:8080"
echo "  Keycloak      : http://keycloak.localtest.me:8080"
echo ""
echo "  Get credentials:"
echo "    bash ${KAGENTI_DIR}/.github/scripts/local-setup/show-services.sh"
echo ""
echo "  Hello Agent (port-forward):"
echo "    kubectl port-forward svc/hello-kagenti-agent 18000:8000 \\"
echo "      -n team1 --context ${KUBECTL_CONTEXT} &"
echo "    curl http://localhost:18000/.well-known/agent-card.json"
echo ""
echo "  Tear down Kind cluster:"
echo "    kind delete cluster --name ${KIND_CLUSTER}"
echo ""
