#!/usr/bin/env bash
set -euo pipefail

SHARED_URL="${1:-https://api.platform.haleops.net/api/health}"
GKE_HOST="${2:-gke-api.platform.haleops.net}"
AKS_HOST="${3:-aks-api.platform.haleops.net}"
REQUESTS="${REQUESTS:-200}"
SLEEP_BETWEEN="${SLEEP_BETWEEN:-0}"

RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
BLUE=$'\033[34m'
RESET=$'\033[0m'

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '%sMissing command: %s%s\n' "${RED}" "$1" "${RESET}" >&2
    exit 1
  fi
}

need_cmd curl
need_cmd dig

ips_for_host() {
  dig +short "$1" | sort -u
}

contains_ip() {
  local needle="$1"
  shift
  for item in "$@"; do
    if [[ "${needle}" == "${item}" ]]; then
      return 0
    fi
  done
  return 1
}

detect_target() {
  local headers body result remote_ip served_by
  headers="$(mktemp)"
  body="$(mktemp)"
  result="$(curl -ksS -o "${body}" -D "${headers}" --max-time 10 -w '%{remote_ip}' "${SHARED_URL}" || true)"
  remote_ip="${result}"
  served_by="$(awk -F': ' 'tolower($1)=="x-served-by" {gsub("\r","",$2); print tolower($2)}' "${headers}" | tail -n1)"
  rm -f "${headers}" "${body}"

  if [[ "${served_by}" == *"gke"* ]]; then
    printf 'gke'
    return 0
  fi

  if [[ "${served_by}" == *"aks"* ]]; then
    printf 'aks'
    return 0
  fi

  if contains_ip "${remote_ip}" "${GKE_IPS[@]}"; then
    printf 'gke'
    return 0
  fi

  if contains_ip "${remote_ip}" "${AKS_IPS[@]}"; then
    printf 'aks'
    return 0
  fi

  printf 'unknown'
}

mapfile -t GKE_IPS < <(ips_for_host "${GKE_HOST}")
mapfile -t AKS_IPS < <(ips_for_host "${AKS_HOST}")

printf '%sGKE IPs:%s %s\n' "${BLUE}" "${RESET}" "${GKE_IPS[*]}"
printf '%sAKS IPs:%s %s\n' "${BLUE}" "${RESET}" "${AKS_IPS[*]}"

gke=0
aks=0
unknown=0

for i in $(seq 1 "${REQUESTS}"); do
  target="$(detect_target)"
  case "${target}" in
    gke) gke=$((gke + 1)) ;;
    aks) aks=$((aks + 1)) ;;
    *) unknown=$((unknown + 1)) ;;
  esac

  if [[ "${SLEEP_BETWEEN}" != "0" ]]; then
    sleep "${SLEEP_BETWEEN}"
  fi
done

total=$((gke + aks + unknown))

pct() {
  python3 - <<'PY' "$1" "$2"
import sys
part = int(sys.argv[1])
total = int(sys.argv[2])
if total == 0:
    print("0.0")
else:
    print(f"{(part / total) * 100:.1f}")
PY
}

printf '\n%sTraffic split over %s requests%s\n' "${GREEN}" "${total}" "${RESET}"
printf '  GKE:     %4s (%s%%)\n' "${gke}" "$(pct "${gke}" "${total}")"
printf '  AKS:     %4s (%s%%)\n' "${aks}" "$(pct "${aks}" "${total}")"
printf '  Unknown: %4s (%s%%)\n' "${unknown}" "$(pct "${unknown}" "${total}")"

if [[ "${unknown}" -gt 0 ]]; then
  printf '%sSome responses could not be mapped back to a cluster. That usually means the shared host moved to a new LB IP before the script refreshed its lookup set.%s\n' "${YELLOW}" "${RESET}"
fi
