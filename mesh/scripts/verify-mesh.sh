#!/usr/bin/env bash
set -euo pipefail

CTX_GKE="${CTX_GKE:-}"
CTX_AKS="${CTX_AKS:-}"
APP_NAMESPACE="${APP_NAMESPACE:-platform}"
TARGET_ISTIO_VERSION="${TARGET_ISTIO_VERSION:-1.29.1}"
TMP_PODS=()

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") --context-gke <context> --context-aks <context>

Flags:
  --context-gke     kubectl context for GKE
  --context-aks     kubectl context for AKS
  --app-namespace   app namespace, default: platform
  --istio-version   printed in the summary, default: 1.29.1
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
    --app-namespace)
      APP_NAMESPACE="$2"
      shift 2
      ;;
    --istio-version)
      TARGET_ISTIO_VERSION="$2"
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
  local item
  for item in "${TMP_PODS[@]:-}"; do
    local ctx="${item%%:*}"
    local pod="${item##*:}"
    kubectl --context "$ctx" delete pod "$pod" -n "$APP_NAMESPACE" --ignore-not-found >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

say() {
  printf '\n==> %s\n' "$*"
}

lb_address() {
  local ctx="$1"
  local ip hostname
  ip="$(kubectl --context "$ctx" get svc istio-eastwestgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  hostname="$(kubectl --context "$ctx" get svc istio-eastwestgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  printf '%s' "${ip:-$hostname}"
}

first_pod_by_label() {
  local ctx="$1"
  local label="$2"
  kubectl --context "$ctx" get pod -n "$APP_NAMESPACE" -l "$label" -o jsonpath='{.items[0].metadata.name}'
}

check_synced_remote_clusters() {
  local ctx="$1"
  local expected_remote="$2"
  local output
  output="$(istioctl remote-clusters --context "$ctx")"
  printf '%s\n' "$output"
  grep -Eq "${expected_remote}[[:space:]].*synced" <<<"$output"
}

run_tls_check() {
  local ctx="$1"
  local pod="$2"

  # Istio dropped authn tls-check a long time ago, so I fall back to x describe on 1.29.
  if istioctl authn tls-check --help >/dev/null 2>&1; then
    istioctl authn tls-check "$pod.$APP_NAMESPACE" api-gateway.platform.svc.cluster.local --context "$ctx"
  else
    local output
    output="$(istioctl x describe pod "$pod" -n "$APP_NAMESPACE" --context "$ctx")"
    printf '%s\n' "$output"
    grep -Eq 'mTLS|ISTIO_MUTUAL|STRICT' <<<"$output"
  fi
}

make_smoke_pod() {
  local ctx="$1"
  local name="mesh-smoke-$(date +%s)-$RANDOM"

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
      image: curlimages/curl:8.8.0
      command: ["sh", "-c", "sleep 600"]
POD

  kubectl --context "$ctx" wait --for=condition=Ready pod/"$name" -n "$APP_NAMESPACE" --timeout=180s >/dev/null
  TMP_PODS+=("${ctx}:${name}")
  printf '%s' "$name"
}

check_remote_endpoints() {
  local ctx="$1"
  local pod="$2"
  local svc_cluster="outbound|8081||order-service.${APP_NAMESPACE}.svc.cluster.local"
  local output

  output="$(istioctl pc endpoints "$pod" -n "$APP_NAMESPACE" --context "$ctx" --cluster "$svc_cluster")"
  printf '%s\n' "$output"
  grep -q '15443' <<<"$output"
}

cross_cluster_http_test() {
  local ctx="$1"
  local pod="$2"
  kubectl --context "$ctx" exec -n "$APP_NAMESPACE" "$pod" -c curl -- sh -c '
    ok=0
    i=1
    while [ "$i" -le 5 ]; do
      curl -fsS http://api-gateway.platform.svc.cluster.local:8080/api/health >/dev/null && ok=$((ok+1))
      i=$((i+1))
    done
    [ "$ok" -eq 5 ]
  '
}

say "checking istiod rollouts"
kubectl --context "$CTX_GKE" rollout status deploy/istiod -n istio-system --timeout=120s
kubectl --context "$CTX_AKS" rollout status deploy/istiod -n istio-system --timeout=120s

say "checking east-west gateway addresses"
printf 'gke: %s\n' "$(lb_address "$CTX_GKE")"
[[ -n "$(lb_address "$CTX_GKE")" ]]
printf 'aks: %s\n' "$(lb_address "$CTX_AKS")"
[[ -n "$(lb_address "$CTX_AKS")" ]]

say "checking remote cluster sync from GKE"
check_synced_remote_clusters "$CTX_GKE" cluster2

say "checking remote cluster sync from AKS"
check_synced_remote_clusters "$CTX_AKS" cluster1

say "checking mTLS view from one pod on each cluster"
GKE_API_POD="$(first_pod_by_label "$CTX_GKE" 'app.kubernetes.io/name=api-gateway')"
AKS_API_POD="$(first_pod_by_label "$CTX_AKS" 'app.kubernetes.io/name=api-gateway')"
run_tls_check "$CTX_GKE" "$GKE_API_POD"
run_tls_check "$CTX_AKS" "$AKS_API_POD"

say "checking remote endpoints on the api-gateway sidecars"
check_remote_endpoints "$CTX_GKE" "$GKE_API_POD"
check_remote_endpoints "$CTX_AKS" "$AKS_API_POD"

say "running cross-cluster HTTP smoke test from injected curl pods"
GKE_SMOKE="$(make_smoke_pod "$CTX_GKE")"
AKS_SMOKE="$(make_smoke_pod "$CTX_AKS")"
cross_cluster_http_test "$CTX_GKE" "$GKE_SMOKE"
cross_cluster_http_test "$CTX_AKS" "$AKS_SMOKE"

printf '\nmesh looks healthy with istioctl %s\n' "$TARGET_ISTIO_VERSION"
# TODO: add a Prometheus query here once I stop moving ports around.
