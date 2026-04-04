#!/usr/bin/env bash
set -euo pipefail

GKE_CONTEXT="${GKE_CONTEXT:-gke-mc-k8s-gke-cluster}"
MONITORING_NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"

cat <<EOF
Grafana URL: http://127.0.0.1:3000
user: admin
password: admin

Ctrl+C stops the port-forward.
EOF

exec kubectl --context "${GKE_CONTEXT}" -n "${MONITORING_NAMESPACE}" port-forward svc/central-grafana 3000:80
