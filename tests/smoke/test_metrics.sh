#!/usr/bin/env bash
set -euo pipefail

CONTEXT="${CONTEXT:-gke}"
MONITORING_NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"
PROM_PORT="${PROM_PORT:-19090}"
THANOS_PORT="${THANOS_PORT:-19091}"
GRAFANA_PORT="${GRAFANA_PORT:-13000}"

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") [--context <kubectl-context>] [--namespace monitoring]
USAGE
}

while (($#)); do
  case "$1" in
    --context)
      CONTEXT="$2"
      shift 2
      ;;
    --namespace)
      MONITORING_NAMESPACE="$2"
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

prom_service="$(kubectl --context "$CONTEXT" -n "$MONITORING_NAMESPACE" get svc -o jsonpath='{range .items[*]}{.metadata.name}{"
"}{end}' | grep '^mc-kps-gke' | grep 'prometheus$' | head -n1)"
[[ -n "$prom_service" ]] || { echo "couldn't find the GKE Prometheus service" >&2; exit 1; }

cleanup() {
  [[ -n "${PROM_PID:-}" ]] && kill "$PROM_PID" >/dev/null 2>&1 || true
  [[ -n "${THANOS_PID:-}" ]] && kill "$THANOS_PID" >/dev/null 2>&1 || true
  [[ -n "${GRAFANA_PID:-}" ]] && kill "$GRAFANA_PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

kubectl --context "$CONTEXT" -n "$MONITORING_NAMESPACE" port-forward "svc/${prom_service}" "${PROM_PORT}:9090" >/tmp/prometheus-pf.log 2>&1 &
PROM_PID=$!
kubectl --context "$CONTEXT" -n "$MONITORING_NAMESPACE" port-forward svc/thanos-query "${THANOS_PORT}:9090" >/tmp/thanos-pf.log 2>&1 &
THANOS_PID=$!
kubectl --context "$CONTEXT" -n "$MONITORING_NAMESPACE" port-forward svc/central-grafana "${GRAFANA_PORT}:80" >/tmp/grafana-pf.log 2>&1 &
GRAFANA_PID=$!

for _ in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:${PROM_PORT}/-/ready" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

for _ in $(seq 1 30); do
  if curl -fsS -u admin:admin "http://127.0.0.1:${GRAFANA_PORT}/api/health" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

query() {
  local port="$1"
  local expr="$2"
  curl -fsS --get "http://127.0.0.1:${port}/api/v1/query" --data-urlencode "query=${expr}"
}

query "$PROM_PORT" 'up' | jq -e '.status == "success"' >/dev/null
query "$PROM_PORT" 'sum(istio_requests_total)' | jq -e '.status == "success"' >/dev/null
query "$PROM_PORT" 'sum(mcplatform_http_requests_total)' | jq -e '.status == "success"' >/dev/null
query "$THANOS_PORT" 'sum by (cluster) (up)' | jq -e '.status == "success"' >/dev/null
curl -fsS -u admin:admin "http://127.0.0.1:${GRAFANA_PORT}/api/health" | jq -e '.database == "ok"' >/dev/null
curl -fsS -u admin:admin "http://127.0.0.1:${GRAFANA_PORT}/api/search" | jq -e 'length >= 1' >/dev/null

echo "metrics smoke checks passed"
