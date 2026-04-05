#!/usr/bin/env bash
set -euo pipefail

SHARED_URL="https://api.platform.haleops.net"
GKE_URL="https://gke-api.platform.haleops.net"
AKS_URL="https://aks-api.platform.haleops.net"
GKE_CONTEXT="${GKE_CONTEXT:-gke}"
AKS_CONTEXT="${AKS_CONTEXT:-aks}"
NAMESPACE="${NAMESPACE:-platform}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --shared-url)
      SHARED_URL="$2"
      shift 2
      ;;
    --gke-url)
      GKE_URL="$2"
      shift 2
      ;;
    --aks-url)
      AKS_URL="$2"
      shift 2
      ;;
    *)
      echo "unknown flag: $1" >&2
      exit 1
      ;;
  esac
done

RED=$'\033[31m'
GREEN=$'\033[32m'
BLUE=$'\033[34m'
RESET=$'\033[0m'

for cmd in kubectl curl istioctl grep; do
  command -v "${cmd}" >/dev/null 2>&1 || { echo "missing command: ${cmd}" >&2; exit 1; }
done

info() {
  printf '%s== %s ==%s\n' "${BLUE}" "$*" "${RESET}"
}

ok() {
  printf '%s✔ %s%s\n' "${GREEN}" "$*" "${RESET}"
}

assert_200() {
  local url="$1"
  local label="$2"
  local code
  code="$(curl -ksS -o /dev/null -w '%{http_code}' "${url}" || true)"
  [[ "${code}" == "200" ]] || { printf '%s%s returned %s%s\n' "${RED}" "${label}" "${code}" "${RESET}" >&2; exit 1; }
  ok "${label}"
}

info "Checking public entrypoints"
assert_200 "${SHARED_URL}/api/health" "shared ingress"
assert_200 "${GKE_URL}/api/health" "gke ingress"
assert_200 "${AKS_URL}/api/health" "aks ingress"

info "Checking remote cluster registration"
istioctl remote-clusters --context "${GKE_CONTEXT}" | grep -q "${AKS_CONTEXT}"
ok "gke sees aks"
istioctl remote-clusters --context "${AKS_CONTEXT}" | grep -q "${GKE_CONTEXT}"
ok "aks sees gke"

info "Checking service discovery from a GKE sidecar"
api_pod="$(kubectl --context "${GKE_CONTEXT}" -n "${NAMESPACE}" get pod -l app.kubernetes.io/name=api-gateway -o jsonpath='{.items[0].metadata.name}')"
[[ -n "${api_pod}" ]] || { echo "api-gateway pod not found in ${GKE_CONTEXT}" >&2; exit 1; }

kubectl --context "${GKE_CONTEXT}" -n "${NAMESPACE}" exec "${api_pod}" -c istio-proxy -- curl -fsS http://127.0.0.1:15000/clusters | grep -q "order-service.${NAMESPACE}.svc.cluster.local"
ok "proxy knows about order-service"

endpoints="$(istioctl proxy-config endpoints "${api_pod}.${NAMESPACE}" \
  --context "${GKE_CONTEXT}" \
  -n "${NAMESPACE}" \
  --cluster "outbound|8081||order-service.${NAMESPACE}.svc.cluster.local" || true)"

printf '%s' "${endpoints}" | grep -q "ENDPOINT"
ok "proxy has outbound endpoints for order-service"

# echo "DEBUG: ${endpoints}"
