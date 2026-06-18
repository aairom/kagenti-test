#!/usr/bin/env bash
# =============================================================================
# test-agent.sh
#
# Tests the Hello Kagenti Agent via its A2A JSON-RPC endpoint.
#
# Starts a kubectl port-forward, fires two requests, then cleans up.
#
# Usage:
#   ./scripts/test-agent.sh
#
# Requirements:
#   - kubectl configured to point at minikube
#   - curl
# =============================================================================
set -euo pipefail

NAMESPACE="team1"
SERVICE="hello-kagenti-agent"
LOCAL_PORT="18000"
REMOTE_PORT="8000"
KUBECTL_CONTEXT="minikube-1"
BASE_URL="http://localhost:${LOCAL_PORT}"

log()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()   { echo -e "\033[1;32m[ OK ]\033[0m  $*"; }
die()  { echo -e "\033[1;31m[ERR ]\033[0m  $*"; exit 1; }

command -v kubectl >/dev/null 2>&1 || die "kubectl not found"
command -v curl    >/dev/null 2>&1 || die "curl not found"

# ── Start port-forward ────────────────────────────────────────────────────────
log "Starting port-forward on ${BASE_URL}…"
kubectl port-forward "svc/${SERVICE}" "${LOCAL_PORT}:${REMOTE_PORT}" -n "${NAMESPACE}" --context "${KUBECTL_CONTEXT}" &
PF_PID=$!
trap 'kill "${PF_PID}" 2>/dev/null || true' EXIT

# Wait for the port-forward to be ready
sleep 2

# ── Health check ──────────────────────────────────────────────────────────────
log "Health check…"
HEALTH=$(curl -sf "${BASE_URL}/health" || echo "FAILED")
echo "  Response: ${HEALTH}"
[[ "${HEALTH}" == *"ok"* ]] && ok "Health check passed" || die "Health check failed"

# ── Agent Card ───────────────────────────────────────────────────────────────
log "Fetching Agent Card…"
curl -sf "${BASE_URL}/.well-known/agent-card.json" | python3 -m json.tool || true
echo ""

# ── Test 1: Hello ─────────────────────────────────────────────────────────────
log "Test 1: Sending 'Hello!'"
MSG_ID1="00000000-0000-0000-0000-000000000001"
RESP1=$(curl -sf -X POST "${BASE_URL}/" \
  -H "Content-Type: application/json" \
  -d "{
    \"jsonrpc\": \"2.0\",
    \"id\": \"${MSG_ID1}\",
    \"method\": \"message/send\",
    \"params\": {
      \"message\": {
        \"role\": \"user\",
        \"parts\": [{\"kind\": \"text\", \"text\": \"Hello!\"}],
        \"messageId\": \"${MSG_ID1}\"
      }
    }
  }" || echo "FAILED")
echo ""
echo "  Response:"
echo "${RESP1}" | python3 -m json.tool 2>/dev/null || echo "${RESP1}"
echo ""

# ── Test 2: Name introduction ─────────────────────────────────────────────────
log "Test 2: Sending 'My name is Alice!'"
MSG_ID2="00000000-0000-0000-0000-000000000002"
RESP2=$(curl -sf -X POST "${BASE_URL}/" \
  -H "Content-Type: application/json" \
  -d "{
    \"jsonrpc\": \"2.0\",
    \"id\": \"${MSG_ID2}\",
    \"method\": \"message/send\",
    \"params\": {
      \"message\": {
        \"role\": \"user\",
        \"parts\": [{\"kind\": \"text\", \"text\": \"My name is Alice!\"}],
        \"messageId\": \"${MSG_ID2}\"
      }
    }
  }" || echo "FAILED")
echo ""
echo "  Response:"
echo "${RESP2}" | python3 -m json.tool 2>/dev/null || echo "${RESP2}"
echo ""

ok "All tests completed."
