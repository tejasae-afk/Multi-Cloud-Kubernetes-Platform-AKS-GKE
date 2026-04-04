#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITORING_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DASHBOARD_DIR="${MONITORING_DIR}/grafana/dashboards"

GKE_CONTEXT="${GKE_CONTEXT:-gke-mc-k8s-gke-cluster}"
AKS_CONTEXT="${AKS_CONTEXT:-aks-mc-k8s-aks}"
MONITORING_NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"
GKE_PROM_RELEASE="${GKE_PROM_RELEASE:-mc-kps-gke}"
AKS_PROM_RELEASE="${AKS_PROM_RELEASE:-mc-kps-aks}"
GRAFANA_RELEASE="${GRAFANA_RELEASE:-central-grafana}"
KPS_CHART_VERSION="${KPS_CHART_VERSION:-82.10.3}"
GRAFANA_CHART_VERSION="${GRAFANA_CHART_VERSION:-10.5.15}"
THANOS_REMOTE_WRITE_USER="${THANOS_REMOTE_WRITE_USER:-remote-write}"
THANOS_REMOTE_WRITE_PASS="${THANOS_REMOTE_WRITE_PASS:-remote-write-dev-password}"

RED="$(printf '\033[31m')"
GREEN="$(printf '\033[32m')"
YELLOW="$(printf '\033[33m')"
BLUE="$(printf '\033[34m')"
BOLD="$(printf '\033[1m')"
RESET="$(printf '\033[0m')"

log() {
  printf "%b[%s]%b %s\n" "${BLUE}${BOLD}" "$1" "${RESET}" "$2"
}

ok() {
  printf "%b[ok]%b %s\n" "${GREEN}${BOLD}" "${RESET}" "$1"
}

warn() {
  printf "%b[warn]%b %s\n" "${YELLOW}${BOLD}" "${RESET}" "$1"
}

die() {
  printf "%b[err]%b %s\n" "${RED}${BOLD}" "${RESET}" "$1" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

check_context() {
  local ctx="$1"
  kubectl config get-contexts -o name | grep -Fxq "$ctx" || die "kubectl context not found: $ctx"
}

create_namespace() {
  local ctx="$1"
  kubectl --context "$ctx" create namespace "$MONITORING_NAMESPACE" --dry-run=client -o yaml | kubectl --context "$ctx" apply -f -
  # I keep monitoring out of sidecar injection because the scrape path gets noisy fast.
  kubectl --context "$ctx" label namespace "$MONITORING_NAMESPACE" istio-injection=disabled --overwrite >/dev/null
}

create_receive_auth_secret() {
  local tmp_auth
  tmp_auth="$(mktemp)"
  printf "%s:%s\n" "${THANOS_REMOTE_WRITE_USER}" "$(openssl passwd -apr1 "${THANOS_REMOTE_WRITE_PASS}")" > "${tmp_auth}"
  kubectl --context "$GKE_CONTEXT" -n "$MONITORING_NAMESPACE" create secret generic thanos-receive-basic-auth     --from-file=auth="${tmp_auth}"     --dry-run=client -o yaml | kubectl --context "$GKE_CONTEXT" apply -f -
  rm -f "${tmp_auth}"
}

create_remote_write_secret() {
  kubectl --context "$AKS_CONTEXT" -n "$MONITORING_NAMESPACE" create secret generic thanos-remote-write-auth     --from-literal=username="${THANOS_REMOTE_WRITE_USER}"     --from-literal=password="${THANOS_REMOTE_WRITE_PASS}"     --dry-run=client -o yaml | kubectl --context "$AKS_CONTEXT" apply -f -
}

wait_for_lb() {
  local ctx="$1"
  local namespace="$2"
  local service="$3"
  local timeout_seconds="${4:-900}"
  local waited=0
  local address=""

  while (( waited < timeout_seconds )); do
    address="$(kubectl --context "$ctx" -n "$namespace" get svc "$service" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
    if [[ -z "$address" ]]; then
      address="$(kubectl --context "$ctx" -n "$namespace" get svc "$service" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
    fi

    if [[ -n "$address" ]]; then
      printf "%s" "$address"
      return 0
    fi

    sleep 10
    waited=$((waited + 10))
    warn "waiting for ${service} load balancer address in ${ctx}..."
  done

  return 1
}

install_gke_stack() {
  log "1/6" "installing kube-prometheus-stack in GKE"
  helm upgrade --install "$GKE_PROM_RELEASE" prometheus-community/kube-prometheus-stack     --kube-context "$GKE_CONTEXT"     --namespace "$MONITORING_NAMESPACE"     --version "$KPS_CHART_VERSION"     -f "${MONITORING_DIR}/prometheus/values-gke.yaml"     --wait     --timeout 20m
  ok "GKE kube-prometheus-stack is up"
}

install_thanos() {
  log "2/6" "applying Thanos Receive and Query in GKE"
  kubectl --context "$GKE_CONTEXT" -n "$MONITORING_NAMESPACE" apply -f "${MONITORING_DIR}/prometheus/thanos-receive.yaml"
  kubectl --context "$GKE_CONTEXT" -n "$MONITORING_NAMESPACE" rollout status deploy/thanos-receive --timeout=10m
  kubectl --context "$GKE_CONTEXT" -n "$MONITORING_NAMESPACE" rollout status deploy/thanos-query --timeout=10m
  ok "Thanos Receive and Query are up"
}

install_aks_stack() {
  local receive_host="$1"
  local tmp_values
  tmp_values="$(mktemp)"
  sed "s|__THANOS_RECEIVE_URL__|http://${receive_host}:10908/api/v1/receive|g" "${MONITORING_DIR}/prometheus/values-aks.yaml" > "${tmp_values}"

  log "3/6" "installing kube-prometheus-stack in AKS"
  helm upgrade --install "$AKS_PROM_RELEASE" prometheus-community/kube-prometheus-stack     --kube-context "$AKS_CONTEXT"     --namespace "$MONITORING_NAMESPACE"     --version "$KPS_CHART_VERSION"     -f "${tmp_values}"     --wait     --timeout 20m

  rm -f "${tmp_values}"
  ok "AKS kube-prometheus-stack is up"
}

apply_rules_and_monitors() {
  local ctx="$1"
  kubectl --context "$ctx" -n "$MONITORING_NAMESPACE" apply -f "${MONITORING_DIR}/prometheus/servicemonitor-app.yaml"
  kubectl --context "$ctx" -n "$MONITORING_NAMESPACE" apply -f "${MONITORING_DIR}/prometheus/alerting-rules.yaml"
  kubectl --context "$ctx" -n "$MONITORING_NAMESPACE" apply -f "${MONITORING_DIR}/alerts/cluster-alerts.yaml"
  kubectl --context "$ctx" -n "$MONITORING_NAMESPACE" apply -f "${MONITORING_DIR}/alerts/mesh-alerts.yaml"
  kubectl --context "$ctx" -n "$MONITORING_NAMESPACE" apply -f "${MONITORING_DIR}/alerts/app-alerts.yaml"
}

load_dashboard_configmaps() {
  local dashboard
  local name
  for dashboard in "${DASHBOARD_DIR}"/*.json; do
    name="grafana-dashboard-$(basename "${dashboard}" .json | tr '_' '-' )"
    kubectl --context "$GKE_CONTEXT" -n "$MONITORING_NAMESPACE" create configmap "$name"       --from-file="$(basename "${dashboard}")=${dashboard}"       --dry-run=client -o yaml | kubectl --context "$GKE_CONTEXT" apply -f -
    kubectl --context "$GKE_CONTEXT" -n "$MONITORING_NAMESPACE" label configmap "$name" grafana_dashboard=1 --overwrite >/dev/null
  done
}

install_grafana() {
  log "4/6" "loading Grafana datasources and dashboards"
  kubectl --context "$GKE_CONTEXT" -n "$MONITORING_NAMESPACE" apply -f "${MONITORING_DIR}/grafana/datasources.yaml"
  load_dashboard_configmaps

  log "5/6" "installing Grafana in GKE"
  helm upgrade --install "$GRAFANA_RELEASE" grafana/grafana     --kube-context "$GKE_CONTEXT"     --namespace "$MONITORING_NAMESPACE"     --version "$GRAFANA_CHART_VERSION"     -f "${MONITORING_DIR}/grafana/values.yaml"     --wait     --timeout 15m

  ok "Grafana is up"
}

print_summary() {
  log "6/6" "final checks"
  kubectl --context "$GKE_CONTEXT" -n "$MONITORING_NAMESPACE" get pods
  kubectl --context "$AKS_CONTEXT" -n "$MONITORING_NAMESPACE" get pods
  kubectl --context "$GKE_CONTEXT" -n "$MONITORING_NAMESPACE" get svc thanos-receive-public thanos-query central-grafana || true
  cat <<EOF

Grafana access:
  ./monitoring/scripts/port-forward-grafana.sh

Default creds:
  user: admin
  password: admin

EOF
}

main() {
  need_cmd kubectl
  need_cmd helm
  need_cmd openssl
  need_cmd sed

  check_context "$GKE_CONTEXT"
  check_context "$AKS_CONTEXT"

  log "repo" "adding Helm repos"
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
  helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
  helm repo update >/dev/null

  create_namespace "$GKE_CONTEXT"
  create_namespace "$AKS_CONTEXT"
  create_receive_auth_secret
  create_remote_write_secret

  install_gke_stack
  install_thanos

  local receive_host
  receive_host="$(wait_for_lb "$GKE_CONTEXT" "$MONITORING_NAMESPACE" thanos-receive-public 900)" || die "timed out waiting for thanos-receive-public"
  ok "Thanos Receive is reachable at ${receive_host}"

  install_aks_stack "$receive_host"

  log "rules" "applying ServiceMonitors and PrometheusRules"
  apply_rules_and_monitors "$GKE_CONTEXT"
  apply_rules_and_monitors "$AKS_CONTEXT"
  ok "rules and monitors are in"

  install_grafana
  print_summary
}

main "$@"
