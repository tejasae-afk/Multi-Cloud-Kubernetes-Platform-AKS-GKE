#!/usr/bin/env bash
set -euo pipefail

GATEWAY_URL="${GATEWAY_URL:-http://localhost:8080}"
DURATION_SECONDS="${DURATION_SECONDS:-300}"
CTX="${CTX:-}"
APP_NAMESPACE="${APP_NAMESPACE:-platform}"

usage() {
  cat <<EOF
usage: $0 [--gateway-url http://localhost:8080] [--duration-seconds 300] [--context <kubectl-context>] [--app-namespace platform]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --gateway-url)
      GATEWAY_URL="$2"
      shift 2
      ;;
    --duration-seconds)
      DURATION_SECONDS="$2"
      shift 2
      ;;
    --context)
      CTX="$2"
      shift 2
      ;;
    --app-namespace)
      APP_NAMESPACE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown arg: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

have_hey=false
have_wrk=false
command -v hey >/dev/null 2>&1 && have_hey=true
command -v wrk >/dev/null 2>&1 && have_wrk=true

if [[ "$have_hey" != true && "$have_wrk" != true ]]; then
  echo "need hey or wrk in PATH" >&2
  exit 1
fi

chaos_inventory_blip() {
  [[ -n "$CTX" ]] || return 0
  command -v kubectl >/dev/null 2>&1 || return 0

  local deploy_name
  deploy_name="$(kubectl --context "$CTX" -n "$APP_NAMESPACE" get deploy -l app.kubernetes.io/name=inventory-service -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  [[ -n "$deploy_name" ]] || return 0

  sleep 120
  kubectl --context "$CTX" -n "$APP_NAMESPACE" scale deploy "$deploy_name" --replicas=0 >/dev/null
  sleep 45
  kubectl --context "$CTX" -n "$APP_NAMESPACE" scale deploy "$deploy_name" --replicas=2 >/dev/null
}

run_with_hey() {
  hey -z "${DURATION_SECONDS}s" -c 30 "${GATEWAY_URL}/api/orders" >/tmp/traffic-orders.log 2>&1 &
  p1=$!
  hey -z "${DURATION_SECONDS}s" -c 10 "${GATEWAY_URL}/api/health" >/tmp/traffic-health.log 2>&1 &
  p2=$!
  hey -z "${DURATION_SECONDS}s" -c 6 "${GATEWAY_URL}/does-not-exist" >/tmp/traffic-404.log 2>&1 &
  p3=$!

  chaos_inventory_blip &
  chaos_pid=$!

  wait "$p1" "$p2" "$p3"
  wait "$chaos_pid" || true
}

run_with_wrk() {
  order_script="$(mktemp)"
  bad_script="$(mktemp)"
  cat > "$order_script" <<'EOF'
request = function()
  return wrk.format("GET", "/api/orders")
end
EOF
  cat > "$bad_script" <<'EOF'
request = function()
  local paths = {"/api/health", "/does-not-exist"}
  local idx = math.random(1, #paths)
  return wrk.format("GET", paths[idx])
end
EOF

  wrk -t4 -c30 -d"${DURATION_SECONDS}s" -s "$order_script" "$GATEWAY_URL" >/tmp/traffic-orders.log 2>&1 &
  p1=$!
  wrk -t2 -c10 -d"${DURATION_SECONDS}s" -s "$bad_script" "$GATEWAY_URL" >/tmp/traffic-mixed.log 2>&1 &
  p2=$!

  chaos_inventory_blip &
  chaos_pid=$!

  wait "$p1" "$p2"
  wait "$chaos_pid" || true
  rm -f "$order_script" "$bad_script"
}

echo "hitting ${GATEWAY_URL} for ${DURATION_SECONDS}s"
# print(f"debug: {response.json()}")
if [[ "$have_hey" == true ]]; then
  run_with_hey
else
  run_with_wrk
fi

echo "done. logs: /tmp/traffic-orders.log /tmp/traffic-health.log /tmp/traffic-404.log /tmp/traffic-mixed.log"
