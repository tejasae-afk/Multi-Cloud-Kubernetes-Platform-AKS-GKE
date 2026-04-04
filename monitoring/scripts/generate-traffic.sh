#!/usr/bin/env bash
set -euo pipefail

API_GATEWAY_URL="${API_GATEWAY_URL:-http://127.0.0.1:8080}"
DURATION_SECONDS="${DURATION_SECONDS:-300}"
CHAOS_CONTEXT="${CHAOS_CONTEXT:-}"
APP_NAMESPACE="${APP_NAMESPACE:-default}"
INVENTORY_DEPLOYMENT="${INVENTORY_DEPLOYMENT:-platform-inventory-service}"
ORDER_CONCURRENCY="${ORDER_CONCURRENCY:-20}"
CANARY_CONCURRENCY="${CANARY_CONCURRENCY:-6}"
HEALTH_CONCURRENCY="${HEALTH_CONCURRENCY:-4}"
MISS_CONCURRENCY="${MISS_CONCURRENCY:-2}"

RED="$(printf '\033[31m')"
GREEN="$(printf '\033[32m')"
BLUE="$(printf '\033[34m')"
BOLD="$(printf '\033[1m')"
RESET="$(printf '\033[0m')"

log() {
  printf "%b[%s]%b %s\n" "${BLUE}${BOLD}" "$1" "${RESET}" "$2"
}

ok() {
  printf "%b[ok]%b %s\n" "${GREEN}${BOLD}" "${RESET}" "$1"
}

die() {
  printf "%b[err]%b %s\n" "${RED}${BOLD}" "${RESET}" "$1" >&2
  exit 1
}

pick_tool() {
  if command -v hey >/dev/null 2>&1; then
    printf "hey"
    return 0
  fi

  if command -v wrk >/dev/null 2>&1; then
    printf "wrk"
    return 0
  fi

  return 1
}

restore_inventory() {
  if [[ -n "${CHAOS_CONTEXT}" && -n "${ORIGINAL_REPLICAS:-}" ]]; then
    kubectl --context "${CHAOS_CONTEXT}" -n "${APP_NAMESPACE}" scale deployment "${INVENTORY_DEPLOYMENT}" --replicas="${ORIGINAL_REPLICAS}" >/dev/null 2>&1 || true
  fi
}

run_hey_mix() {
  hey -z "${DURATION_SECONDS}s" -c "${ORDER_CONCURRENCY}" "${API_GATEWAY_URL}/api/orders" &
  hey -z "${DURATION_SECONDS}s" -c "${CANARY_CONCURRENCY}" -H "x-route-to: aks" "${API_GATEWAY_URL}/api/orders" &
  hey -z "${DURATION_SECONDS}s" -c "${HEALTH_CONCURRENCY}" "${API_GATEWAY_URL}/api/health" &
  hey -z "${DURATION_SECONDS}s" -c "${MISS_CONCURRENCY}" "${API_GATEWAY_URL}/api/not-found" &
  wait
}

run_wrk_mix() {
  wrk -t2 -c"${ORDER_CONCURRENCY}" -d"${DURATION_SECONDS}s" "${API_GATEWAY_URL}/api/orders" &
  wrk -t2 -c"${CANARY_CONCURRENCY}" -d"${DURATION_SECONDS}s" -H "x-route-to: aks" "${API_GATEWAY_URL}/api/orders" &
  wrk -t1 -c"${HEALTH_CONCURRENCY}" -d"${DURATION_SECONDS}s" "${API_GATEWAY_URL}/api/health" &
  wrk -t1 -c"${MISS_CONCURRENCY}" -d"${DURATION_SECONDS}s" "${API_GATEWAY_URL}/api/not-found" &
  wait
}

chaos_burst() {
  [[ -z "${CHAOS_CONTEXT}" ]] && return 0

  ORIGINAL_REPLICAS="$(kubectl --context "${CHAOS_CONTEXT}" -n "${APP_NAMESPACE}" get deployment "${INVENTORY_DEPLOYMENT}" -o jsonpath='{.spec.replicas}')"
  sleep 120

  log "chaos" "scaling ${INVENTORY_DEPLOYMENT} down for a short burst so the 5xx panels stop looking dead"
  kubectl --context "${CHAOS_CONTEXT}" -n "${APP_NAMESPACE}" scale deployment "${INVENTORY_DEPLOYMENT}" --replicas=0
  sleep 45
  kubectl --context "${CHAOS_CONTEXT}" -n "${APP_NAMESPACE}" scale deployment "${INVENTORY_DEPLOYMENT}" --replicas="${ORIGINAL_REPLICAS}"
  ok "inventory deployment is back at ${ORIGINAL_REPLICAS} replicas"
}

main() {
  local tool
  tool="$(pick_tool)" || die "install hey or wrk first"

  trap restore_inventory EXIT

  log "traffic" "running mixed traffic against ${API_GATEWAY_URL} for ${DURATION_SECONDS}s"
  if [[ -n "${CHAOS_CONTEXT}" ]]; then
    log "traffic" "chaos burst is on via ${CHAOS_CONTEXT}; that gives me a short 5xx spike in the order path"
    chaos_burst &
  else
    log "traffic" "chaos burst is off; 4xx is guaranteed, 5xx only shows up if a dependency is already unhappy"
  fi

  # print(f"debug: {response.json()}")
  case "${tool}" in
    hey)
      run_hey_mix
      ;;
    wrk)
      run_wrk_mix
      ;;
    *)
      die "unsupported tool: ${tool}"
      ;;
  esac

  ok "traffic run finished"
}

main "$@"
