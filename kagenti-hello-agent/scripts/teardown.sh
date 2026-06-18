#!/usr/bin/env bash
# =============================================================================
# teardown.sh  —  Remove the Hello Kagenti Agent from the cluster
#
# Usage:
#   ./scripts/teardown.sh
#   ./scripts/teardown.sh --all   # also remove the kagenti-system namespace (operator)
# =============================================================================
set -euo pipefail

KUBECTL_CONTEXT="minikube-1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_MANIFEST="${SCRIPT_DIR}/../k8s/deploy.yaml"

REMOVE_ALL=false
for arg in "$@"; do
  case $arg in
    --all) REMOVE_ALL=true ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done

log()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()   { echo -e "\033[1;32m[ OK ]\033[0m  $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m  $*"; }

log "Removing Hello Kagenti Agent from cluster (context: ${KUBECTL_CONTEXT})…"
kubectl --context "${KUBECTL_CONTEXT}" delete -f "${K8S_MANIFEST}" --ignore-not-found=true
ok "Agent resources removed (namespace team1, deployment, service, AgentRuntime)"

if [[ "${REMOVE_ALL}" == "true" ]]; then
  warn "Removing Kagenti Operator (kagenti-system namespace)…"
  helm --kube-context "${KUBECTL_CONTEXT}" uninstall kagenti-operator \
    -n kagenti-system --ignore-not-found 2>/dev/null || true
  kubectl --context "${KUBECTL_CONTEXT}" delete namespace kagenti-system \
    --ignore-not-found=true 2>/dev/null || true
  ok "Kagenti Operator removed"

  warn "Removing cert-manager…"
  kubectl --context "${KUBECTL_CONTEXT}" delete \
    -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.3/cert-manager.yaml \
    --ignore-not-found=true 2>/dev/null || true
  ok "cert-manager removed"
fi

echo ""
echo "Done. To stop the cluster entirely:"
echo "  minikube stop --profile ${KUBECTL_CONTEXT}"
echo ""
echo "To stop the Podman machine (frees host RAM):"
echo "  podman machine stop podman-machine-default"
