#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MESH_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ISTIO_DIR="${MESH_DIR}/istio"
CERTS_DIR="${MESH_DIR}/certs/output"

CTX_GKE="${CTX_GKE:-}"
CTX_AKS="${CTX_AKS:-}"
APP_NAMESPACE="${APP_NAMESPACE:-platform}"
TARGET_ISTIO_VERSION="${TARGET_ISTIO_VERSION:-1.29.1}"
START_FROM=1
CURRENT_STEP=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") --context-gke <context> --context-aks <context> [--start-from <step>]

Flags:
  --context-gke     kubectl context for GKE
  --context-aks     kubectl context for AKS
  --app-namespace   app namespace, default: platform
  --istio-version   expected istioctl client version, default: 1.29.1
  --start-from      numeric step to resume from
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
    --start-from)
      START_FROM="$2"
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

fail_with_resume() {
  local code=$?
  printf "${RED}step %s failed${NC}\n" "$CURRENT_STEP" >&2
  printf "${YELLOW}resume with:${NC} %s --context-gke %s --context-aks %s --app-namespace %s --istio-version %s --start-from %s\n" \
    "$0" "$CTX_GKE" "$CTX_AKS" "$APP_NAMESPACE" "$TARGET_ISTIO_VERSION" "$CURRENT_STEP" >&2
  exit "$code"
}
trap fail_with_resume ERR

step_msg() {
  CURRENT_STEP="$1"
  shift
  printf "${BLUE}[%02d]${NC} %s\n" "$CURRENT_STEP" "$*"
}

ok_msg() {
  printf "${GREEN}done${NC}\n\n"
}

require_context() {
  local ctx="$1"
  kubectl config get-contexts -o name | grep -Fxq "$ctx"
}

label_istio_namespace() {
  local ctx="$1"
  local network="$2"
  kubectl --context "$ctx" create namespace istio-system --dry-run=client -o yaml | kubectl --context "$ctx" apply -f - >/dev/null
  kubectl --context "$ctx" label namespace istio-system topology.istio.io/network="$network" --overwrite >/dev/null
}

apply_cacerts() {
  local ctx="$1"
  local cluster_dir="$2"

  [[ -f "$cluster_dir/ca-cert.pem" ]]
  [[ -f "$cluster_dir/ca-key.pem" ]]
  [[ -f "$cluster_dir/root-cert.pem" ]]
  [[ -f "$cluster_dir/cert-chain.pem" ]]

  kubectl --context "$ctx" create secret generic cacerts \
    -n istio-system \
    --from-file=ca-cert.pem="$cluster_dir/ca-cert.pem" \
    --from-file=ca-key.pem="$cluster_dir/ca-key.pem" \
    --from-file=root-cert.pem="$cluster_dir/root-cert.pem" \
    --from-file=cert-chain.pem="$cluster_dir/cert-chain.pem" \
    --dry-run=client -o yaml | kubectl --context "$ctx" apply -f - >/dev/null
}

wait_for_lb() {
  local ctx="$1"
  local timeout_seconds="$2"
  local start_ts
  start_ts="$(date +%s)"

  while true; do
    local ip hostname
    ip="$(kubectl --context "$ctx" get svc istio-eastwestgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
    hostname="$(kubectl --context "$ctx" get svc istio-eastwestgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"

    if [[ -n "$ip" || -n "$hostname" ]]; then
      printf '  %s\n' "${ip:-$hostname}"
      return 0
    fi

    if (( $(date +%s) - start_ts >= timeout_seconds )); then
      echo "timed out waiting for istio-eastwestgateway on ${ctx}" >&2
      # kubectl --context "$ctx" describe svc istio-eastwestgateway -n istio-system
      return 1
    fi

    sleep 10
  done
}

step_1() {
  step_msg 1 "checking kube contexts"
  require_context "$CTX_GKE"
  require_context "$CTX_AKS"
  ok_msg
}

step_2() {
  step_msg 2 "checking istioctl client version"
  local client_version
  client_version="$(istioctl version --remote=false 2>/dev/null | awk '/client version/ {print $3}' | head -n1)"
  client_version="${client_version%%-*}"
  [[ "$client_version" == "$TARGET_ISTIO_VERSION" ]]
  ok_msg
}

step_3() {
  step_msg 3 "making sure istio-system exists on both clusters"
  label_istio_namespace "$CTX_GKE" network1
  label_istio_namespace "$CTX_AKS" network2
  ok_msg
}

step_4() {
  step_msg 4 "installing cluster CAs as cacerts secrets"
  apply_cacerts "$CTX_GKE" "$CERTS_DIR/cluster1"
  apply_cacerts "$CTX_AKS" "$CERTS_DIR/cluster2"
  ok_msg
}

step_5() {
  step_msg 5 "installing Istio on GKE"
  istioctl install --context "$CTX_GKE" -f "$ISTIO_DIR/install-gke.yaml" -y
  kubectl --context "$CTX_GKE" rollout status deploy/istiod -n istio-system --timeout=300s
  ok_msg
}

step_6() {
  step_msg 6 "installing Istio on AKS"
  istioctl install --context "$CTX_AKS" -f "$ISTIO_DIR/install-aks.yaml" -y
  kubectl --context "$CTX_AKS" rollout status deploy/istiod -n istio-system --timeout=300s
  ok_msg
}

step_7() {
  step_msg 7 "deploying east-west gateway on GKE"
  istioctl install --context "$CTX_GKE" -f "$ISTIO_DIR/east-west-gw-gke.yaml" -y
  kubectl --context "$CTX_GKE" apply -f "$ISTIO_DIR/expose-services-gke.yaml"
  kubectl --context "$CTX_GKE" rollout status deploy/istio-eastwestgateway -n istio-system --timeout=300s
  ok_msg
}

step_8() {
  step_msg 8 "deploying east-west gateway on AKS"
  istioctl install --context "$CTX_AKS" -f "$ISTIO_DIR/east-west-gw-aks.yaml" -y
  kubectl --context "$CTX_AKS" apply -f "$ISTIO_DIR/expose-services-aks.yaml"
  kubectl --context "$CTX_AKS" rollout status deploy/istio-eastwestgateway -n istio-system --timeout=300s
  ok_msg
}

step_9() {
  step_msg 9 "waiting for east-west gateway addresses"
  printf '  gke: '
  wait_for_lb "$CTX_GKE" 900
  printf '  aks: '
  wait_for_lb "$CTX_AKS" 900
  ok_msg
}

step_10() {
  step_msg 10 "exchanging remote secrets"
  istioctl create-remote-secret --context "$CTX_GKE" --name cluster1 | kubectl --context "$CTX_AKS" apply -f - >/dev/null
  istioctl create-remote-secret --context "$CTX_AKS" --name cluster2 | kubectl --context "$CTX_GKE" apply -f - >/dev/null
  ok_msg
}

step_11() {
  step_msg 11 "applying mesh-wide STRICT mTLS"
  kubectl --context "$CTX_GKE" apply -f "$ISTIO_DIR/peer-authentication.yaml" >/dev/null
  kubectl --context "$CTX_AKS" apply -f "$ISTIO_DIR/peer-authentication.yaml" >/dev/null
  ok_msg
}

step_12() {
  step_msg 12 "running mesh verification"
  "${SCRIPT_DIR}/verify-mesh.sh" \
    --context-gke "$CTX_GKE" \
    --context-aks "$CTX_AKS" \
    --app-namespace "$APP_NAMESPACE" \
    --istio-version "$TARGET_ISTIO_VERSION"
  ok_msg
}

for step in $(seq "$START_FROM" 12); do
  "step_${step}"
done

printf "${GREEN}mesh setup finished${NC}\n"
# GKE east-west gw came up fine. AKS LB stuck Pending - investigating.
# TODO: teach this script to rotate remote secrets instead of just reapplying them.
