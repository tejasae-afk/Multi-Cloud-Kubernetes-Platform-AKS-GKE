#!/usr/bin/env bash
set -euo pipefail

CTX_GKE="${CTX_GKE:-}"
CTX_AKS="${CTX_AKS:-}"
PUBLIC_HOST="${PUBLIC_HOST:-}"
APP_NAMESPACE="${APP_NAMESPACE:-platform}"
RELEASE_NAME="${RELEASE_NAME:-mc-platform}"
TMP_PODS=()

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") --context-gke <context> --context-aks <context> [--public-host api.platform.example.com]
USAGE
}

while (($#)); do
  case "$1" in
    --context-gke)
      CTX_GKE="$2"
      shift 2
      ;;
    --context-aks)
      CTX_AKS="$2"
      shift 2
      ;;
    --public-host)
      PUBLIC_HOST="$2"
      shift 2
      ;;
    --app-namespace)
      APP_NAMESPACE="$2"
      shift 2
      ;;
    --release-name)
      RELEASE_NAME="$2"
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

[[ -n "$CTX_GKE" ]] || { echo "--context-gke is required" >&2; exit 1; }
[[ -n "$CTX_AKS" ]] || { echo "--context-aks is required" >&2; exit 1; }

cleanup() {
  local item ctx pod
  for item in "${TMP_PODS[@]:-}"; do
    ctx="${item%%:*}"
    pod="${item##*:}"
    kubectl --context "$ctx" -n "$APP_NAMESPACE" delete pod "$pod" --ignore-not-found >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

make_curl_pod() {
  local ctx="$1"
  local name="cross-cluster-check-$(date +%s)-$RANDOM"

  cat <<POD | kubectl --context "$ctx" apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ${name}
  namespace: ${APP_NAMESPACE}
  annotations:
    sidecar.istio.io/inject: "true"
spec:
  restartPolicy: Never
  containers:
    - name: curl
      image: curlimages/curl:8.12.1
      command: ["sh", "-c", "sleep 300"]
POD

  kubectl --context "$ctx" -n "$APP_NAMESPACE" wait --for=condition=Ready pod/"$name" --timeout=180s >/dev/null
  TMP_PODS+=("${ctx}:${name}")
  printf '%s' "$name"
}

./mesh/scripts/verify-mesh.sh --context-gke "$CTX_GKE" --context-aks "$CTX_AKS" --app-namespace "$APP_NAMESPACE" --istio-version 1.29.1 >/tmp/mesh-verify.out

for ctx in "$CTX_GKE" "$CTX_AKS"; do
  pod="$(make_curl_pod "$ctx")"
  kubectl --context "$ctx" -n "$APP_NAMESPACE" exec "$pod" -c curl -- curl -fsS "http://${RELEASE_NAME}-order-service.${APP_NAMESPACE}.svc.cluster.local:8081/orders" >/tmp/orders.json
  kubectl --context "$ctx" -n "$APP_NAMESPACE" exec "$pod" -c curl -- curl -fsS "http://${RELEASE_NAME}-inventory-service.${APP_NAMESPACE}.svc.cluster.local:8082/inventory" >/tmp/inventory.json
  istioctl pc endpoints "$pod" -n "$APP_NAMESPACE" --context "$ctx" --cluster "outbound|8081||${RELEASE_NAME}-order-service.${APP_NAMESPACE}.svc.cluster.local" | tee /tmp/mesh-endpoints.txt
  grep -q '15443' /tmp/mesh-endpoints.txt
  # kubectl --context "$ctx" -n "$APP_NAMESPACE" exec "$pod" -c curl -- nslookup "${RELEASE_NAME}-order-service.${APP_NAMESPACE}.svc.cluster.local"
done

if [[ -n "$PUBLIC_HOST" ]]; then
  curl -fsS -H "x-route-to: gke" "http://${PUBLIC_HOST}/api/health" >/dev/null
  curl -fsS -H "x-route-to: aks" "http://${PUBLIC_HOST}/api/health" >/dev/null
fi

echo "cross-cluster integration checks passed"
