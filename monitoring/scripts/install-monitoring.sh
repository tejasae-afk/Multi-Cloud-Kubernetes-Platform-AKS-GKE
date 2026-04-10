#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CTX_GKE="${CTX_GKE:-}"
CTX_AKS="${CTX_AKS:-}"
MON_NS="${MON_NS:-monitoring}"
APP_NAMESPACE="${APP_NAMESPACE:-platform}"
KPS_VERSION="${KPS_VERSION:-82.1.1}"
GRAFANA_CHART_VERSION="${GRAFANA_CHART_VERSION:-10.6.0}"
HELM_TIMEOUT="${HELM_TIMEOUT:-15m}"

usage() {
  cat <<EOF
usage: $0 --gke-context <context> --aks-context <context> [--monitoring-namespace monitoring] [--app-namespace platform]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --gke-context)
      CTX_GKE="$2"
      shift 2
      ;;
    --aks-context)
      CTX_AKS="$2"
      shift 2
      ;;
    --monitoring-namespace)
      MON_NS="$2"
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

if [[ -z "$CTX_GKE" || -z "$CTX_AKS" ]]; then
  usage >&2
  exit 1
fi

say() {
  printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

die() {
  echo "error: $*" >&2
  exit 1
}

need_bin() {
  command -v "$1" >/dev/null 2>&1 || die "missing binary: $1"
}

need_bin kubectl
need_bin helm
need_bin envsubst
need_bin openssl
need_bin awk
need_bin base64

kubectl config get-contexts "$CTX_GKE" >/dev/null 2>&1 || die "missing kubectl context $CTX_GKE"
kubectl config get-contexts "$CTX_AKS" >/dev/null 2>&1 || die "missing kubectl context $CTX_AKS"

wait_rollout() {
  local ctx="$1"
  local ns="$2"
  local kind_name="$3"
  kubectl --context "$ctx" -n "$ns" rollout status "$kind_name" --timeout=10m
}

wait_for_lb() {
  local ctx="$1"
  local ns="$2"
  local svc="$3"
  local lb=""

  for _ in $(seq 1 60); do
    lb="$(kubectl --context "$ctx" -n "$ns" get svc "$svc" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
    if [[ -z "$lb" ]]; then
      lb="$(kubectl --context "$ctx" -n "$ns" get svc "$svc" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
    fi

    if [[ -n "$lb" ]]; then
      printf '%s' "$lb"
      return 0
    fi

    sleep 10
  done

  return 1
}

create_secret_if_missing() {
  local ctx="$1"
  local ns="$2"
  local name="$3"
  local user_key="$4"
  local user_val="$5"
  local pass_key="$6"
  local pass_val="$7"

  if kubectl --context "$ctx" -n "$ns" get secret "$name" >/dev/null 2>&1; then
    return 0
  fi

  kubectl --context "$ctx" -n "$ns" create secret generic "$name" \
    --from-literal="$user_key=$user_val" \
    --from-literal="$pass_key=$pass_val"
}

apply_configmap_from_file() {
  local ctx="$1"
  local ns="$2"
  local name="$3"
  local file="$4"
  local key_name="$5"
  local label_key="$6"
  local label_value="$7"
  local folder="${8:-}"

  kubectl --context "$ctx" -n "$ns" delete configmap "$name" --ignore-not-found >/dev/null
  kubectl --context "$ctx" -n "$ns" create configmap "$name" --from-file="$key_name=$file"
  kubectl --context "$ctx" -n "$ns" label configmap "$name" "$label_key=$label_value" --overwrite >/dev/null
  kubectl --context "$ctx" -n "$ns" label configmap "$name" app.kubernetes.io/part-of=multi-cloud-k8s --overwrite >/dev/null
  if [[ -n "$folder" ]]; then
    kubectl --context "$ctx" -n "$ns" annotate configmap "$name" grafana_folder="$folder" --overwrite >/dev/null
  fi
}

say "adding helm repos"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update >/dev/null

say "creating namespaces"
kubectl --context "$CTX_GKE" create namespace "$MON_NS" >/dev/null 2>&1 || true
kubectl --context "$CTX_AKS" create namespace "$MON_NS" >/dev/null 2>&1 || true

say "installing kube-prometheus-stack on GKE"
helm upgrade --install mc-monitoring-gke prometheus-community/kube-prometheus-stack \
  --version "$KPS_VERSION" \
  --namespace "$MON_NS" \
  --create-namespace \
  --kube-context "$CTX_GKE" \
  --wait \
  --timeout "$HELM_TIMEOUT" \
  -f "$ROOT_DIR/monitoring/prometheus/values-gke.yaml"

say "applying ServiceMonitors and alerts on GKE"
kubectl --context "$CTX_GKE" -n "$MON_NS" apply -f "$ROOT_DIR/monitoring/prometheus/servicemonitor-app.yaml"
kubectl --context "$CTX_GKE" -n "$MON_NS" apply -f "$ROOT_DIR/monitoring/alerts/cluster-alerts.yaml"
kubectl --context "$CTX_GKE" -n "$MON_NS" apply -f "$ROOT_DIR/monitoring/alerts/mesh-alerts.yaml"
kubectl --context "$CTX_GKE" -n "$MON_NS" apply -f "$ROOT_DIR/monitoring/alerts/app-alerts.yaml"

say "making auth token for Thanos Receive"
if ! kubectl --context "$CTX_GKE" -n "$MON_NS" get secret thanos-receive-auth >/dev/null 2>&1; then
  kubectl --context "$CTX_GKE" -n "$MON_NS" create secret generic thanos-receive-auth \
    --from-literal=token="$(openssl rand -hex 24)"
fi
THANOS_RECEIVE_TOKEN="$(kubectl --context "$CTX_GKE" -n "$MON_NS" get secret thanos-receive-auth -o jsonpath='{.data.token}' | base64 --decode)"
export THANOS_RECEIVE_TOKEN

say "deploying Thanos Receive and Query on GKE"
kubectl --context "$CTX_GKE" apply -f "$ROOT_DIR/monitoring/prometheus/thanos-receive.yaml"
wait_rollout "$CTX_GKE" "$MON_NS" deployment/thanos-receive
wait_rollout "$CTX_GKE" "$MON_NS" deployment/thanos-query

say "waiting for the Thanos Receive load balancer"
THANOS_RECEIVE_HOST="$(wait_for_lb "$CTX_GKE" "$MON_NS" thanos-receive-external)" || die "thanos-receive-external never got an address"
THANOS_RECEIVE_URL="http://${THANOS_RECEIVE_HOST}:19291/api/v1/receive"
export THANOS_RECEIVE_URL

say "installing kube-prometheus-stack on AKS"
TMP_AKS_VALUES="$(mktemp)"
envsubst < "$ROOT_DIR/monitoring/prometheus/values-aks.yaml" > "$TMP_AKS_VALUES"
helm upgrade --install mc-monitoring-aks prometheus-community/kube-prometheus-stack \
  --version "$KPS_VERSION" \
  --namespace "$MON_NS" \
  --create-namespace \
  --kube-context "$CTX_AKS" \
  --wait \
  --timeout "$HELM_TIMEOUT" \
  -f "$TMP_AKS_VALUES"
rm -f "$TMP_AKS_VALUES"

say "applying ServiceMonitors and alerts on AKS"
kubectl --context "$CTX_AKS" -n "$MON_NS" apply -f "$ROOT_DIR/monitoring/prometheus/servicemonitor-app.yaml"
kubectl --context "$CTX_AKS" -n "$MON_NS" apply -f "$ROOT_DIR/monitoring/alerts/cluster-alerts.yaml"
kubectl --context "$CTX_AKS" -n "$MON_NS" apply -f "$ROOT_DIR/monitoring/alerts/mesh-alerts.yaml"
kubectl --context "$CTX_AKS" -n "$MON_NS" apply -f "$ROOT_DIR/monitoring/alerts/app-alerts.yaml"

say "making Grafana admin creds"
if ! kubectl --context "$CTX_GKE" -n "$MON_NS" get secret grafana-admin >/dev/null 2>&1; then
  kubectl --context "$CTX_GKE" -n "$MON_NS" create secret generic grafana-admin \
    --from-literal=admin-user=admin \
    --from-literal=admin-password="$(openssl rand -base64 24 | tr -d '=+/\n' | cut -c1-20)"
fi

say "figuring out the local Prometheus service name"
PROM_SVC="$(kubectl --context "$CTX_GKE" -n "$MON_NS" get svc --no-headers | awk '/mc-monitoring-gke/ && /prometheus/ {print $1; exit}')"
[[ -n "$PROM_SVC" ]] || die "could not find the GKE Prometheus service"
PROMETHEUS_URL="http://${PROM_SVC}.${MON_NS}.svc.cluster.local:9090"
THANOS_URL="http://thanos-query.${MON_NS}.svc.cluster.local:9090"
export PROMETHEUS_URL THANOS_URL

say "loading Grafana datasources and dashboards"
TMP_DS="$(mktemp)"
envsubst < "$ROOT_DIR/monitoring/grafana/datasources.yaml" > "$TMP_DS"
apply_configmap_from_file "$CTX_GKE" "$MON_NS" grafana-datasources "$TMP_DS" datasources.yaml grafana_datasource 1
rm -f "$TMP_DS"

apply_configmap_from_file "$CTX_GKE" "$MON_NS" grafana-dashboard-overview "$ROOT_DIR/monitoring/grafana/dashboards/multi-cluster-overview.json" multi-cluster-overview.json grafana_dashboard 1 overview
apply_configmap_from_file "$CTX_GKE" "$MON_NS" grafana-dashboard-mesh "$ROOT_DIR/monitoring/grafana/dashboards/istio-mesh.json" istio-mesh.json grafana_dashboard 1 mesh
apply_configmap_from_file "$CTX_GKE" "$MON_NS" grafana-dashboard-app "$ROOT_DIR/monitoring/grafana/dashboards/app-metrics.json" app-metrics.json grafana_dashboard 1 applications
apply_configmap_from_file "$CTX_GKE" "$MON_NS" grafana-dashboard-infra "$ROOT_DIR/monitoring/grafana/dashboards/infrastructure.json" infrastructure.json grafana_dashboard 1 infrastructure

say "installing Grafana"
helm upgrade --install mc-grafana grafana/grafana \
  --version "$GRAFANA_CHART_VERSION" \
  --namespace "$MON_NS" \
  --create-namespace \
  --kube-context "$CTX_GKE" \
  --wait \
  --timeout "$HELM_TIMEOUT" \
  -f "$ROOT_DIR/monitoring/grafana/values.yaml"

wait_rollout "$CTX_GKE" "$MON_NS" deployment/mc-grafana

ADMIN_USER="$(kubectl --context "$CTX_GKE" -n "$MON_NS" get secret grafana-admin -o jsonpath='{.data.admin-user}' | base64 --decode)"
ADMIN_PASS="$(kubectl --context "$CTX_GKE" -n "$MON_NS" get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 --decode)"

say "done"
echo "Grafana URL: http://localhost:3000"
echo "Grafana user: ${ADMIN_USER}"
echo "Grafana password: ${ADMIN_PASS}"
echo "Port forward with: ./monitoring/scripts/port-forward-grafana.sh --context ${CTX_GKE} --namespace ${MON_NS}"
echo "Thanos receive URL used by AKS: ${THANOS_RECEIVE_URL}"
# good enough for now
