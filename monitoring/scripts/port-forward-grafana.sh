#!/usr/bin/env bash
set -euo pipefail

CTX="${CTX:-}"
MON_NS="${MON_NS:-monitoring}"

usage() {
  echo "usage: $0 --context <context> [--namespace monitoring]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --context)
      CTX="$2"
      shift 2
      ;;
    --namespace)
      MON_NS="$2"
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

[[ -n "$CTX" ]] || { usage >&2; exit 1; }

user="$(kubectl --context "$CTX" -n "$MON_NS" get secret grafana-admin -o jsonpath='{.data.admin-user}' | base64 --decode)"
pass="$(kubectl --context "$CTX" -n "$MON_NS" get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 --decode)"

echo "Grafana: http://localhost:3000"
echo "user: $user"
echo "password: $pass"
exec kubectl --context "$CTX" -n "$MON_NS" port-forward svc/mc-grafana 3000:80
