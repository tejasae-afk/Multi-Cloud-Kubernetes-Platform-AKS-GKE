#!/usr/bin/env bash
set -euo pipefail

CONTEXT=""
NAMESPACE="platform"
BASE_URL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --context)
      CONTEXT="$2"
      shift 2
      ;;
    --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --base-url)
      BASE_URL="$2"
      shift 2
      ;;
    *)
      echo "unknown flag: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "${CONTEXT}" ]]; then
  echo "--context is required" >&2
  exit 1
fi

RED=$'\033[31m'
GREEN=$'\033[32m'
BLUE=$'\033[34m'
RESET=$'\033[0m'

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '%sMissing command: %s%s\n' "${RED}" "$1" "${RESET}" >&2
    exit 1
  fi
}

for cmd in kubectl curl grep; do
  need_cmd "${cmd}"
done

info() {
  printf '%s== %s ==%s\n' "${BLUE}" "$*" "${RESET}"
}

ok() {
  printf '%s✔ %s%s\n' "${GREEN}" "$*" "${RESET}"
}

svc_name() {
  local app="$1"
  kubectl --context "${CONTEXT}" -n "${NAMESPACE}" get svc \
    -l "app.kubernetes.io/name=${app}" \
    -o jsonpath='{.items[0].metadata.name}'
}

assert_200() {
  local url="$1"
  local label="$2"
  local code
  code="$(curl -ksS -o /dev/null -w '%{http_code}' "${url}" || true)"
  if [[ "${code}" != "200" ]]; then
    printf '%sExpected 200 from %s but got %s%s\n' "${RED}" "${label}" "${code}" "${RESET}" >&2
    exit 1
  fi
  ok "${label}"
}

PORT_FWDS=()
cleanup() {
  for pid in "${PORT_FWDS[@]:-}"; do
    kill "${pid}" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

forward_service() {
  local service_name="$1"
  local local_port="$2"
  local remote_port="$3"
  kubectl --context "${CONTEXT}" -n "${NAMESPACE}" port-forward "svc/${service_name}" "${local_port}:${remote_port}" >/tmp/"${service_name}".pf.log 2>&1 &
  PORT_FWDS+=("$!")
  sleep 3
}

info "Waiting for deployments"
kubectl --context "${CONTEXT}" -n "${NAMESPACE}" wait deploy -l app.kubernetes.io/part-of=multi-cloud-k8s --for=condition=Available --timeout=5m >/dev/null

api_service="$(svc_name "api-gateway")"
order_service="$(svc_name "order-service")"
inventory_service="$(svc_name "inventory-service")"

[[ -n "${api_service}" ]] || { echo "api-gateway service not found" >&2; exit 1; }
[[ -n "${order_service}" ]] || { echo "order-service service not found" >&2; exit 1; }
[[ -n "${inventory_service}" ]] || { echo "inventory-service service not found" >&2; exit 1; }

info "Port-forwarding services from ${CONTEXT}"
forward_service "${api_service}" 18080 8080
forward_service "${order_service}" 18081 8081
forward_service "${inventory_service}" 18082 8082

assert_200 "http://127.0.0.1:18080/healthz" "api-gateway /healthz"
assert_200 "http://127.0.0.1:18080/readyz" "api-gateway /readyz"
assert_200 "http://127.0.0.1:18080/metrics" "api-gateway /metrics"

assert_200 "http://127.0.0.1:18081/healthz" "order-service /healthz"
assert_200 "http://127.0.0.1:18081/readyz" "order-service /readyz"
assert_200 "http://127.0.0.1:18081/orders" "order-service /orders"
assert_200 "http://127.0.0.1:18081/metrics" "order-service /metrics"

assert_200 "http://127.0.0.1:18082/healthz" "inventory-service /healthz"
assert_200 "http://127.0.0.1:18082/readyz" "inventory-service /readyz"
assert_200 "http://127.0.0.1:18082/inventory" "inventory-service /inventory"
assert_200 "http://127.0.0.1:18082/metrics" "inventory-service /metrics"

if [[ -n "${BASE_URL}" ]]; then
  assert_200 "${BASE_URL}/api/health" "public /api/health"
fi

# echo "DEBUG: ${api_service} ${order_service} ${inventory_service}"
