#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MESH_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CTX_GKE="${CTX_GKE:-}"
CTX_AKS="${CTX_AKS:-}"
APP_NAMESPACE="${APP_NAMESPACE:-platform}"
OUTPUT_DIR="${OUTPUT_DIR:-${MESH_DIR}/debug/$(date +%Y%m%d-%H%M%S)}"
DNS_PODS=()

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") --context-gke <context> --context-aks <context>

Flags:
  --context-gke     kubectl context for GKE
  --context-aks     kubectl context for AKS
  --app-namespace   app namespace, default: platform
  --output-dir      dump directory, default: mesh/debug/<timestamp>
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
    --output-dir)
      OUTPUT_DIR="$2"
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

mkdir -p "$OUTPUT_DIR"

cleanup() {
  local item
  for item in "${DNS_PODS[@]:-}"; do
    local ctx="${item%%:*}"
    local pod="${item##*:}"
    kubectl --context "$ctx" delete pod "$pod" -n "$APP_NAMESPACE" --ignore-not-found >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

capture() {
  local name="$1"
  shift
  {
    printf '$'
    for arg in "$@"; do
      printf ' %q' "$arg"
    done
    printf '\n\n'
    "$@"
  } >"$OUTPUT_DIR/$name.txt" 2>&1 || true
}

make_dns_pod() {
  local ctx="$1"
  local name="mesh-dns-$(date +%s)-$RANDOM"

  cat <<POD | kubectl --context "$ctx" apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ${name}
  namespace: ${APP_NAMESPACE}
spec:
  restartPolicy: Never
  containers:
    - name: busybox
      image: busybox:1.36.1
      command: ["sh", "-c", "sleep 300"]
POD

  kubectl --context "$ctx" wait --for=condition=Ready pod/"$name" -n "$APP_NAMESPACE" --timeout=120s >/dev/null 2>&1 || true
  DNS_PODS+=("${ctx}:${name}")
  printf '%s' "$name"
}

capture gke-remote-clusters istioctl remote-clusters --context "$CTX_GKE"
capture aks-remote-clusters istioctl remote-clusters --context "$CTX_AKS"

capture gke-proxy-status istioctl proxy-status --context "$CTX_GKE"
capture aks-proxy-status istioctl proxy-status --context "$CTX_AKS"

capture gke-analyze istioctl analyze -A --context "$CTX_GKE"
capture aks-analyze istioctl analyze -A --context "$CTX_AKS"

capture gke-istio-pods kubectl --context "$CTX_GKE" get pods -n istio-system -o wide
capture aks-istio-pods kubectl --context "$CTX_AKS" get pods -n istio-system -o wide

capture gke-eastwest-svc kubectl --context "$CTX_GKE" get svc istio-eastwestgateway -n istio-system -o yaml
capture aks-eastwest-svc kubectl --context "$CTX_AKS" get svc istio-eastwestgateway -n istio-system -o yaml

capture gke-eastwest-logs kubectl --context "$CTX_GKE" logs deploy/istio-eastwestgateway -n istio-system --tail=300
capture aks-eastwest-logs kubectl --context "$CTX_AKS" logs deploy/istio-eastwestgateway -n istio-system --tail=300

capture gke-istiod-logs kubectl --context "$CTX_GKE" logs deploy/istiod -n istio-system --tail=300
capture aks-istiod-logs kubectl --context "$CTX_AKS" logs deploy/istiod -n istio-system --tail=300

capture gke-platform-pods kubectl --context "$CTX_GKE" get pods -n "$APP_NAMESPACE" -o wide
capture aks-platform-pods kubectl --context "$CTX_AKS" get pods -n "$APP_NAMESPACE" -o wide

capture gke-endpointslices kubectl --context "$CTX_GKE" get endpointslices -n "$APP_NAMESPACE" -o wide
capture aks-endpointslices kubectl --context "$CTX_AKS" get endpointslices -n "$APP_NAMESPACE" -o wide

GKE_DNS_POD="$(make_dns_pod "$CTX_GKE")"
AKS_DNS_POD="$(make_dns_pod "$CTX_AKS")"

capture gke-dns-test kubectl --context "$CTX_GKE" exec -n "$APP_NAMESPACE" "$GKE_DNS_POD" -- nslookup api-gateway.platform.svc.cluster.local
capture aks-dns-test kubectl --context "$CTX_AKS" exec -n "$APP_NAMESPACE" "$AKS_DNS_POD" -- nslookup api-gateway.platform.svc.cluster.local

printf 'wrote mesh dump to %s\n' "$OUTPUT_DIR"
# good enough for now
# TODO: dump envoy config only when I ask for it. It gets noisy fast.
