#!/usr/bin/env bash
# =============================================================================
# setup-podman-machine.sh
#
# Resizes the default Podman machine to support the Kagenti full platform.
#
# The Podman machine must be STOPPED before memory can be changed.
# This script stops it, resizes to 12 GB / 6 CPUs, then restarts it.
#
# Usage:
#   ./scripts/setup-podman-machine.sh [--memory MiB] [--cpus N]
#
# Defaults:
#   --memory  12288  (12 GB — covers UI + Keycloak + SPIRE with headroom)
#   --cpus    6
#
# Requirements:
#   - podman CLI
#   - Mac with ≥16 GB RAM (verified: 36 GB)
# =============================================================================
set -euo pipefail

MACHINE_NAME="podman-machine-default"
TARGET_MEMORY=12288   # MiB — 12 GB
TARGET_CPUS=6

for arg in "$@"; do
  case $arg in
    --memory) TARGET_MEMORY="$2"; shift 2 ;;
    --cpus)   TARGET_CPUS="$2";   shift 2 ;;
  esac
done

log()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()   { echo -e "\033[1;32m[ OK ]\033[0m  $*"; }
die()  { echo -e "\033[1;31m[ERR ]\033[0m  $*"; exit 1; }

command -v podman >/dev/null 2>&1 || die "podman not found"

# ── Current state ─────────────────────────────────────────────────────────────
CURRENT_MEMORY=$(podman machine inspect "${MACHINE_NAME}" \
  --format '{{.Resources.Memory}}' 2>/dev/null || echo 0)
CURRENT_STATE=$(podman machine list --format json 2>/dev/null \
  | python3 -c "import sys,json; ms=json.load(sys.stdin); print(next((m.get('Running') and 'running' or 'stopped' for m in ms if m['Name']=='${MACHINE_NAME}'), 'not-found'))")

log "Machine    : ${MACHINE_NAME}"
log "State      : ${CURRENT_STATE}"
log "Current RAM: ${CURRENT_MEMORY} MiB"
log "Target RAM : ${TARGET_MEMORY} MiB"
log "Target CPUs: ${TARGET_CPUS}"

if [[ "${CURRENT_MEMORY}" -ge "${TARGET_MEMORY}" ]]; then
  ok "Machine already has ≥${TARGET_MEMORY} MiB RAM — no resize needed"
  if [[ "${CURRENT_STATE}" != "running" ]]; then
    log "Starting machine..."
    podman machine start "${MACHINE_NAME}"
    ok "Machine started"
  fi
  exit 0
fi

# ── Stop the machine ──────────────────────────────────────────────────────────
if [[ "${CURRENT_STATE}" == "running" ]]; then
  log "Stopping Podman machine (required before resize)..."
  podman machine stop "${MACHINE_NAME}"
  ok "Machine stopped"
else
  log "Machine is already stopped"
fi

# ── Resize ───────────────────────────────────────────────────────────────────
log "Setting memory=${TARGET_MEMORY} MiB, cpus=${TARGET_CPUS}..."
podman machine set \
  --memory "${TARGET_MEMORY}" \
  --cpus "${TARGET_CPUS}" \
  "${MACHINE_NAME}"
ok "Machine resized"

# ── Restart ──────────────────────────────────────────────────────────────────
log "Starting Podman machine..."
podman machine start "${MACHINE_NAME}"
ok "Machine started"

# ── Verify ───────────────────────────────────────────────────────────────────
NEW_MEMORY=$(podman machine inspect "${MACHINE_NAME}" \
  --format '{{.Resources.Memory}}' 2>/dev/null || echo 0)
log "Verified RAM: ${NEW_MEMORY} MiB"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Podman machine resized and running"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Memory : ${NEW_MEMORY} MiB"
echo "  CPUs   : ${TARGET_CPUS}"
echo ""
echo "  Next step — Path A (minikube):"
echo "    ./scripts/setup-full-platform.sh"
echo ""
echo "  Next step — Path B (Kind):"
echo "    ./scripts/setup-kind-platform.sh"
echo ""
