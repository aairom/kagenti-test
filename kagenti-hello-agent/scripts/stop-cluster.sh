#!/usr/bin/env bash
# =============================================================================
# stop-cluster.sh  —  Stop the minikube cluster and Podman machine
#
# Preserves all Helm releases, namespaces, and persistent volumes on disk.
# Resume later with:
#   podman machine start podman-machine-default
#   minikube start --profile minikube-1 \
#     --driver=podman --container-runtime=cri-o --memory=7500 --cpus=4
# =============================================================================
set -euo pipefail

MINIKUBE_PROFILE="minikube-1"
KUBECTL_CONTEXT="minikube-1"
PODMAN_MACHINE="podman-machine-default"

log()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()   { echo -e "\033[1;32m[ OK ]\033[0m  $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
step() { echo -e "\n\033[1;35m──── $* ────\033[0m"; }

# ── Kill any active port-forwards ─────────────────────────────────────────────
step "Stopping kubectl port-forward processes"
PF_PIDS=$(pgrep -f "kubectl.*port-forward.*${KUBECTL_CONTEXT}\|kubectl.*port-forward.*minikube-1\|kubectl.*port-forward.*team1\|kubectl.*port-forward.*kagenti-system" 2>/dev/null || true)
if [[ -n "${PF_PIDS}" ]]; then
  echo "${PF_PIDS}" | xargs kill 2>/dev/null || true
  ok "Killed port-forward processes: $(echo "${PF_PIDS}" | tr '\n' ' ')"
else
  log "No active port-forward processes found"
fi

# ── Stop minikube cluster ─────────────────────────────────────────────────────
step "Stopping minikube cluster (profile: ${MINIKUBE_PROFILE})"
if minikube status --profile "${MINIKUBE_PROFILE}" 2>/dev/null | grep -q "Running\|host: Running"; then
  minikube stop --profile "${MINIKUBE_PROFILE}"
  ok "minikube cluster stopped"
else
  warn "minikube cluster '${MINIKUBE_PROFILE}' is not running — nothing to stop"
fi

# ── Stop Podman machine ───────────────────────────────────────────────────────
step "Stopping Podman machine (frees ~8 GiB RAM from your Mac)"
if podman machine list 2>/dev/null | grep "${PODMAN_MACHINE}" | grep -q "running\|Currently running"; then
  podman machine stop "${PODMAN_MACHINE}"
  ok "Podman machine stopped"
else
  warn "Podman machine '${PODMAN_MACHINE}' already stopped"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅  Cluster stopped. All data preserved. Your Mac RAM is free."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  To resume:"
echo "    podman machine start ${PODMAN_MACHINE}"
echo "    minikube start --profile ${MINIKUBE_PROFILE} \\"
echo "      --driver=podman --container-runtime=cri-o --memory=7500 --cpus=4"
echo ""
