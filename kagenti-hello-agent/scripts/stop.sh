#!/usr/bin/env bash
# =============================================================================
# stop.sh  —  Stop the entire Hello Kagenti Agent application
#
# Three modes:
#
#   ./scripts/stop.sh              # default: pause the cluster (resume later)
#   ./scripts/stop.sh --destroy    # delete the cluster entirely (all data lost)
#   ./scripts/stop.sh --agent-only # remove only the agent, leave platform running
#
# Default (pause) is safe: all Helm releases, namespaces, and volumes are
# preserved on disk. Resume with: minikube start --profile minikube-1 ...
#
# --destroy removes the minikube cluster and deletes all Kubernetes state.
# Use this when you want a completely clean slate next time.
#
# In all cases the script also kills any kubectl port-forward processes that
# were forwarding cluster traffic to localhost.
# =============================================================================
set -euo pipefail

MINIKUBE_PROFILE="minikube-1"
KUBECTL_CONTEXT="minikube-1"
PODMAN_MACHINE="podman-machine-default"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_MANIFEST="${SCRIPT_DIR}/../k8s/deploy.yaml"

# ── Parse flags ───────────────────────────────────────────────────────────────
MODE="pause"   # default
for arg in "$@"; do
  case $arg in
    --destroy)    MODE="destroy"    ;;
    --agent-only) MODE="agent-only" ;;
    --help|-h)
      echo "Usage: $0 [--destroy | --agent-only]"
      echo ""
      echo "  (no flag)      Pause the minikube cluster. Resume later with:"
      echo "                   minikube start --profile ${MINIKUBE_PROFILE} \\"
      echo "                     --driver=podman --container-runtime=cri-o \\"
      echo "                     --memory=7500 --cpus=4"
      echo ""
      echo "  --agent-only   Remove only the hello-kagenti-agent from team1."
      echo "                 The Kagenti platform keeps running."
      echo ""
      echo "  --destroy      Delete the cluster entirely (irreversible)."
      echo "                 Next run will need a full reinstall."
      exit 0
      ;;
    *) echo "Unknown option: $arg  (use --help for usage)"; exit 1 ;;
  esac
done

# ── Helpers ───────────────────────────────────────────────────────────────────
log()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()   { echo -e "\033[1;32m[ OK ]\033[0m  $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
step() { echo -e "\n\033[1;35m──── $* ────\033[0m"; }

# ── Kill port-forwards ────────────────────────────────────────────────────────
kill_port_forwards() {
  step "Stopping kubectl port-forward processes"
  # Find all port-forward processes for this cluster
  PF_PIDS=$(pgrep -f "kubectl.*port-forward.*${KUBECTL_CONTEXT}\|kubectl.*port-forward.*minikube-1\|kubectl.*port-forward.*team1\|kubectl.*port-forward.*kagenti-system" 2>/dev/null || true)
  if [[ -n "${PF_PIDS}" ]]; then
    echo "${PF_PIDS}" | xargs kill 2>/dev/null || true
    ok "Killed port-forward processes: $(echo "${PF_PIDS}" | tr '\n' ' ')"
  else
    log "No active port-forward processes found"
  fi
}

# ═════════════════════════════════════════════════════════════════════════════
# MODE: agent-only
# ═════════════════════════════════════════════════════════════════════════════
if [[ "${MODE}" == "agent-only" ]]; then
  step "Removing hello-kagenti-agent only (platform stays up)"
  kill_port_forwards

  log "Deleting agent resources from namespace team1…"
  kubectl --context "${KUBECTL_CONTEXT}" delete \
    -f "${K8S_MANIFEST}" --ignore-not-found=true

  ok "Agent removed. Kagenti platform is still running."
  echo ""
  echo "  Redeploy the agent:  ./scripts/build-and-deploy.sh"
  echo "  Check platform:      kubectl --context ${KUBECTL_CONTEXT} get pods -A"
  exit 0
fi

# ═════════════════════════════════════════════════════════════════════════════
# MODE: pause (default)
# ═════════════════════════════════════════════════════════════════════════════
if [[ "${MODE}" == "pause" ]]; then
  echo ""
  echo "  ┌─────────────────────────────────────────────────────────────┐"
  echo "  │  PAUSING the minikube cluster                               │"
  echo "  │  All Helm releases, namespaces, and data are preserved.     │"
  echo "  │  The cluster can be resumed at any time.                    │"
  echo "  └─────────────────────────────────────────────────────────────┘"
  echo ""

  kill_port_forwards

  step "Stopping minikube cluster (profile: ${MINIKUBE_PROFILE})"
  if minikube status --profile "${MINIKUBE_PROFILE}" 2>/dev/null | grep -q "Running\|host: Running"; then
    minikube stop --profile "${MINIKUBE_PROFILE}"
    ok "minikube cluster stopped"
  else
    warn "minikube cluster '${MINIKUBE_PROFILE}' is not running — nothing to stop"
  fi

  step "Stopping Podman machine (frees ~8 GiB RAM from your Mac)"
  if podman machine list 2>/dev/null | grep "${PODMAN_MACHINE}" | grep -q "running\|Currently running"; then
    podman machine stop "${PODMAN_MACHINE}"
    ok "Podman machine stopped"
  else
    warn "Podman machine '${PODMAN_MACHINE}' is already stopped"
  fi

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  ✅  Everything stopped. Your Mac RAM is free."
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "  To resume later:"
  echo "    podman machine start ${PODMAN_MACHINE}"
  echo "    minikube start --profile ${MINIKUBE_PROFILE} \\"
  echo "      --driver=podman --container-runtime=cri-o --memory=7500 --cpus=4"
  echo ""
  echo "  Then restart port-forwards (see Docs/AccessGuide.md):"
  echo "    kubectl --context ${KUBECTL_CONTEXT} port-forward \\"
  echo "      -n kagenti-system svc/http-istio-np 19080:80 &"
  echo "    kubectl --context ${KUBECTL_CONTEXT} port-forward \\"
  echo "      -n team1 svc/hello-kagenti-agent 18000:8000 &"
  exit 0
fi

# ═════════════════════════════════════════════════════════════════════════════
# MODE: destroy
# ═════════════════════════════════════════════════════════════════════════════
if [[ "${MODE}" == "destroy" ]]; then
  echo ""
  echo "  ┌─────────────────────────────────────────────────────────────┐"
  echo "  │  ⚠️  DESTROY MODE                                           │"
  echo "  │  This will DELETE the minikube cluster entirely.            │"
  echo "  │  All Kubernetes state (Helm releases, namespaces, secrets,  │"
  echo "  │  persistent volumes) will be permanently lost.              │"
  echo "  └─────────────────────────────────────────────────────────────┘"
  echo ""
  read -r -p "  Are you sure? Type YES to proceed: " CONFIRM
  if [[ "${CONFIRM}" != "YES" ]]; then
    echo "  Aborted."
    exit 0
  fi
  echo ""

  kill_port_forwards

  # 1. Remove agent resources first (clean namespace finalizers)
  step "1/4  Removing agent resources (team1)"
  kubectl --context "${KUBECTL_CONTEXT}" delete \
    -f "${K8S_MANIFEST}" --ignore-not-found=true 2>/dev/null || true
  ok "Agent resources removed"

  # 2. Uninstall Helm releases in reverse dependency order
  step "2/4  Uninstalling Helm releases"

  for release_ns in "kagenti:kagenti-system" "kagenti-deps:kagenti-system" "istiod:istio-system" "istio-base:istio-system"; do
    RELEASE="${release_ns%%:*}"
    NS="${release_ns##*:}"
    if helm --kube-context "${KUBECTL_CONTEXT}" list -n "${NS}" 2>/dev/null | grep -q "^${RELEASE}"; then
      log "Uninstalling ${RELEASE} from ${NS}…"
      helm --kube-context "${KUBECTL_CONTEXT}" uninstall "${RELEASE}" \
        -n "${NS}" --wait --timeout=60s 2>/dev/null || true
      ok "${RELEASE} uninstalled"
    else
      warn "${RELEASE} not found in ${NS} — skipping"
    fi
  done

  # 3. Delete the minikube cluster
  step "3/4  Deleting minikube cluster '${MINIKUBE_PROFILE}'"
  minikube delete --profile "${MINIKUBE_PROFILE}" 2>/dev/null || true
  ok "minikube cluster deleted"

  # 4. Stop Podman machine
  step "4/4  Stopping Podman machine"
  if podman machine list 2>/dev/null | grep "${PODMAN_MACHINE}" | grep -q "running\|Currently running"; then
    podman machine stop "${PODMAN_MACHINE}"
    ok "Podman machine stopped (RAM freed)"
  else
    warn "Podman machine '${PODMAN_MACHINE}' already stopped"
  fi

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  ✅  Cluster destroyed. Everything cleaned up."
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "  To start fresh next time:"
  echo "    ./scripts/setup-cluster.sh        # minimal (operator only)"
  echo "    ./scripts/setup-full-platform.sh  # full Kagenti stack"
  exit 0
fi
