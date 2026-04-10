#!/usr/bin/env bash
set -euo pipefail

PUBLIC_HOST="${PUBLIC_HOST:-}"
SCHEME="${SCHEME:-http}"
PATH_VALUE="${PATH_VALUE:-/api/health}"
GKE_CONTEXT="${GKE_CONTEXT:-gke}"
AKS_CONTEXT="${AKS_CONTEXT:-aks}"
INGRESS_NAMESPACE="${INGRESS_NAMESPACE:-istio-system}"
INGRESS_DEPLOYMENT="${INGRESS_DEPLOYMENT:-istio-ingressgateway}"
WAIT_TIMEOUT_SECONDS="${WAIT_TIMEOUT_SECONDS:-240}"
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-10}"

RED='[0;31m'
GREEN='[0;32m'
YELLOW='[1;33m'
BLUE='[0;34m'
NC='[0m'

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") --public-host <host> [--scheme http|https] [--path /api/health]
USAGE
}

while (($#)); do
  case "$1" in
    --public-host)
      PUBLIC_HOST="$2"
      shift 2
      ;;
    --scheme)
      SCHEME="$2"
      shift 2
      ;;
    --path)
      PATH_VALUE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown flag: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

[[ -n "$PUBLIC_HOST" ]] || { echo "--public-host is required" >&2; exit 1; }

step() {
  printf "${BLUE}==>${NC} %s
" "$*"
}

ok() {
  printf "${GREEN}%s${NC}
" "$*"
}

warn() {
  printf "${YELLOW}%s${NC}
" "$*"
}

fail() {
  printf "${RED}%s${NC}
" "$*" >&2
  exit 1
}

wait_for_header() {
  local wanted="$1"
  local hits=0
  local started_at
  started_at="$(date +%s)"

  while (( $(date +%s) - started_at < WAIT_TIMEOUT_SECONDS )); do
    headers="$(mktemp)"
    code="$(curl -sS -D "$headers" -o /dev/null -w '%{http_code}' "${SCHEME}://${PUBLIC_HOST}${PATH_VALUE}")"
    served_by="$(awk -F': ' 'tolower($1)=="x-served-by" {print $2}' "$headers" | tr -d '' | tail -n1)"
    rm -f "$headers"

    if [[ "$code" == "200" && "$served_by" == "$wanted" ]]; then
      hits=$((hits + 1))
    else
      hits=0
    fi

    if (( hits >= 4 )); then
      return 0
    fi

    sleep "$POLL_INTERVAL_SECONDS"
  done

  return 1
}

original_replicas="$(kubectl --context "$GKE_CONTEXT" -n "$INGRESS_NAMESPACE" get deploy "$INGRESS_DEPLOYMENT" -o jsonpath='{.spec.replicas}')"
trap 'kubectl --context "$GKE_CONTEXT" -n "$INGRESS_NAMESPACE" scale deploy "$INGRESS_DEPLOYMENT" --replicas="$original_replicas" >/dev/null 2>&1 || true' EXIT

step "checking weighted traffic before the failure"
./routing/scripts/traffic-split-test.sh --public-host "$PUBLIC_HOST" --scheme "$SCHEME" --path "$PATH_VALUE" --requests 40 >/tmp/pre-failover.txt
cat /tmp/pre-failover.txt

grep -q '^gke:' /tmp/pre-failover.txt || fail "didn't see gke responses before the failure"
grep -q '^aks:' /tmp/pre-failover.txt || fail "didn't see aks responses before the failure"
ok "both clusters are serving before the test"

step "taking GKE ingress down"
kubectl --context "$GKE_CONTEXT" -n "$INGRESS_NAMESPACE" scale deploy "$INGRESS_DEPLOYMENT" --replicas=0 >/dev/null

step "waiting for Traffic Manager to settle on AKS"
if wait_for_header "aks"; then
  ok "Traffic Manager failed over to AKS"
else
  fail "public host never settled on the AKS edge"
fi

step "bringing GKE ingress back"
kubectl --context "$GKE_CONTEXT" -n "$INGRESS_NAMESPACE" scale deploy "$INGRESS_DEPLOYMENT" --replicas="$original_replicas" >/dev/null
kubectl --context "$GKE_CONTEXT" -n "$INGRESS_NAMESPACE" rollout status deploy "$INGRESS_DEPLOYMENT" --timeout=300s >/dev/null

step "waiting for weighted traffic to return"
for _ in $(seq 1 12); do
  ./routing/scripts/traffic-split-test.sh --public-host "$PUBLIC_HOST" --scheme "$SCHEME" --path "$PATH_VALUE" --requests 20 >/tmp/post-failover.txt
  cat /tmp/post-failover.txt
  if grep -q '^gke: [1-9]' /tmp/post-failover.txt && grep -q '^aks: [1-9]' /tmp/post-failover.txt; then
    ok "weighted traffic came back"
    trap - EXIT
    exit 0
  fi
  sleep "$POLL_INTERVAL_SECONDS"
done

fail "public traffic didn't rebalance after GKE came back"
