#!/usr/bin/env bash
set -euo pipefail

CONTEXT=""
MONITORING_NAMESPACE="monitoring"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --context)
      CONTEXT="$2"
      shift 2
      ;;
    --monitoring-namespace)
      MONITORING_NAMESPACE="$2"
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

first_match_service() {
  local pattern="$1"
  kubectl --context "${CONTEXT}" -n "${MONITORING_NAMESPACE}" get svc -o name | grep "${pattern}" | head -n1 | cut -d/ -f2
}

PORT_FWDS=()
cleanup() {
  for pid in "${PORT_FWDS[@]:-}"; do
    kill "${pid}" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

port_forward() {
  local svc_name="$1"
  local local_port="$2"
  local remote_port="$3"
  kubectl --context "${CONTEXT}" -n "${MONITORING_NAMESPACE}" port-forward "svc/${svc_name}" "${local_port}:${remote_port}" >/tmp/"${svc_name}".pf.log 2>&1 &
  PORT_FWDS+=("$!")
  sleep 3
}

prometheus_service="$(first_match_service 'prometheus')"
grafana_service="$(first_match_service 'grafana')"

[[ -n "${prometheus_service}" ]] || { echo "prometheus service not found" >&2; exit 1; }
[[ -n "${grafana_service}" ]] || { echo "grafana service not found" >&2; exit 1; }

info "Port-forwarding monitoring services from ${CONTEXT}"
port_forward "${prometheus_service}" 19090 9090
port_forward "${grafana_service}" 13000 80

ready="$(curl -sS http://127.0.0.1:19090/-/ready || true)"
[[ "${ready}" == "Prometheus is Ready." ]] || { echo "prometheus readiness check failed" >&2; exit 1; }
ok "prometheus ready"

grafana_health="$(curl -sS http://127.0.0.1:13000/api/health || true)"
printf '%s' "${grafana_health}" | grep -q '"database":"ok"'
ok "grafana health endpoint"

query_ok() {
  local query="$1"
  local body
  body="$(curl -sS --get --data-urlencode "query=${query}" http://127.0.0.1:19090/api/v1/query || true)"
  printf '%s' "${body}" | grep -q '"status":"success"' && printf '%s' "${body}" | grep -q '"result":\['
}

query_ok "up" && ok "up metric exists"
query_ok "istio_requests_total" && ok "istio_requests_total exists"

if query_ok "http_requests_total"; then
  ok "http_requests_total exists"
elif query_ok "http_server_requests_total"; then
  ok "http_server_requests_total exists"
elif query_ok "flask_http_request_total"; then
  ok "flask_http_request_total exists"
else
  echo "could not find an expected app request metric" >&2
  exit 1
fi
