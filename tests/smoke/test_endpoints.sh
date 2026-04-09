#!/usr/bin/env bash
set -euo pipefail

CONTEXT="${CONTEXT:-}"
BASE_URL="${BASE_URL:-}"
HOST_HEADER="${HOST_HEADER:-}"
NAMESPACE="${NAMESPACE:-platform}"
RELEASE_NAME="${RELEASE_NAME:-mc-platform}"
INSECURE=false

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") [--context <kubectl-context> --namespace platform --release-name mc-platform]
  $(basename "$0") [--base-url <url> --host-header api.platform.example.com]
USAGE
}

while (($#)); do
  case "$1" in
    --context)
      CONTEXT="$2"
      shift 2
      ;;
    --base-url)
      BASE_URL="$2"
      shift 2
      ;;
    --host-header)
      HOST_HEADER="$2"
      shift 2
      ;;
    --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --release-name)
      RELEASE_NAME="$2"
      shift 2
      ;;
    --insecure)
      INSECURE=true
      shift
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

curl_args=(-fsS)
if [[ "$INSECURE" == true ]]; then
  curl_args+=(-k)
fi
if [[ -n "$HOST_HEADER" ]]; then
  curl_args+=(-H "Host: ${HOST_HEADER}")
fi

check_url() {
  local url="$1"
  echo "checking ${url}"
  curl "${curl_args[@]}" "$url" >/tmp/endpoint.out
  # cat /tmp/endpoint.out
}

if [[ -n "$BASE_URL" ]]; then
  check_url "${BASE_URL}/healthz"
  check_url "${BASE_URL}/api/health"
  check_url "${BASE_URL}/api/orders"
  echo "endpoint smoke checks passed"
  exit 0
fi

[[ -n "$CONTEXT" ]] || { echo "either --context or --base-url is required" >&2; exit 1; }

API_PORT="${API_PORT:-18080}"
ORDER_PORT="${ORDER_PORT:-18081}"
INVENTORY_PORT="${INVENTORY_PORT:-18082}"

cleanup() {
  [[ -n "${API_PID:-}" ]] && kill "$API_PID" >/dev/null 2>&1 || true
  [[ -n "${ORDER_PID:-}" ]] && kill "$ORDER_PID" >/dev/null 2>&1 || true
  [[ -n "${INVENTORY_PID:-}" ]] && kill "$INVENTORY_PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

kubectl --context "$CONTEXT" -n "$NAMESPACE" port-forward "svc/${RELEASE_NAME}-api-gateway" "${API_PORT}:8080" >/tmp/api-pf.log 2>&1 &
API_PID=$!
kubectl --context "$CONTEXT" -n "$NAMESPACE" port-forward "svc/${RELEASE_NAME}-order-service" "${ORDER_PORT}:8081" >/tmp/order-pf.log 2>&1 &
ORDER_PID=$!
kubectl --context "$CONTEXT" -n "$NAMESPACE" port-forward "svc/${RELEASE_NAME}-inventory-service" "${INVENTORY_PORT}:8082" >/tmp/inventory-pf.log 2>&1 &
INVENTORY_PID=$!

for _ in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:${API_PORT}/healthz" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

check_url "http://127.0.0.1:${API_PORT}/healthz"
check_url "http://127.0.0.1:${API_PORT}/api/health"
check_url "http://127.0.0.1:${API_PORT}/api/orders"
check_url "http://127.0.0.1:${ORDER_PORT}/healthz"
check_url "http://127.0.0.1:${ORDER_PORT}/orders"
check_url "http://127.0.0.1:${INVENTORY_PORT}/healthz"
check_url "http://127.0.0.1:${INVENTORY_PORT}/inventory"

echo "endpoint smoke checks passed"
