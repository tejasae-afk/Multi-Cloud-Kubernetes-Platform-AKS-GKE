#!/usr/bin/env bash
set -euo pipefail

SHARED_HOST="${1:-api.platform.haleops.net}"
TM_HOST="${2:-mc-k8s-edge.trafficmanager.net}"
GKE_HOST="${3:-gke-api.platform.haleops.net}"
AKS_HOST="${4:-aks-api.platform.haleops.net}"

RED=$'\033[31m'
GREEN=$'\033[32m'
BLUE=$'\033[34m'
RESET=$'\033[0m'

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '%sMissing command: %s%s\n' "${RED}" "$1" "${RESET}" >&2
    exit 1
  fi
}

need_cmd dig
need_cmd curl

print_block() {
  local title="$1"
  printf '\n%s== %s ==%s\n' "${BLUE}" "${title}" "${RESET}"
}

show_records() {
  local host="$1"
  print_block "${host}"
  printf 'CNAME:\n'
  dig +short CNAME "${host}" || true
  printf '\nA:\n'
  dig +short A "${host}" || true
  printf '\nAAAA:\n'
  dig +short AAAA "${host}" || true
}

probe() {
  local host="$1"
  local result code remote
  result="$(curl -ksS -o /dev/null -D - -w '\n%{http_code}|%{remote_ip}\n' "https://${host}/healthz" || true)"
  code="$(printf '%s' "${result}" | tail -n1 | cut -d'|' -f1)"
  remote="$(printf '%s' "${result}" | tail -n1 | cut -d'|' -f2)"
  printf 'HTTPS /healthz -> code=%s remote_ip=%s\n' "${code}" "${remote}"
}

show_records "${SHARED_HOST}"
show_records "${TM_HOST}"
show_records "${GKE_HOST}"
show_records "${AKS_HOST}"

print_block "HTTP checks"
probe "${SHARED_HOST}"
probe "${GKE_HOST}"
probe "${AKS_HOST}"

# echo "DEBUG: $(dig +short ${SHARED_HOST})"

printf '\n%sDone. If the shared host does not CNAME to the Traffic Manager profile, fix the public zone first.%s\n' "${GREEN}" "${RESET}"
