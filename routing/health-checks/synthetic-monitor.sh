#!/usr/bin/env bash
set -euo pipefail

RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
BLUE=$'\033[34m'
RESET=$'\033[0m'

URL="${1:-https://api.platform.haleops.net/healthz}"
COUNT="${COUNT:-0}"
INTERVAL="${INTERVAL:-5}"
LOG_FILE="${LOG_FILE:-routing/health-checks/synthetic-monitor.log}"

usage() {
  cat <<EOF
Usage:
  ./routing/health-checks/synthetic-monitor.sh [url]

Environment:
  COUNT=0        run forever when set to 0
  INTERVAL=5     seconds between probes
  LOG_FILE=...   append CSV-style output here

Output columns:
  timestamp,status,latency_ms,remote_ip,served_by,resolved
EOF
}

if [[ "${URL}" == "--help" || "${URL}" == "-h" ]]; then
  usage
  exit 0
fi

mkdir -p "$(dirname "${LOG_FILE}")"

resolve_target() {
  local host
  host="$(python3 - <<'PY' "$1"
import sys
from urllib.parse import urlparse
print(urlparse(sys.argv[1]).hostname or sys.argv[1])
PY
)"

  if command -v dig >/dev/null 2>&1; then
    dig +short "${host}" | paste -sd'|' -
  elif command -v getent >/dev/null 2>&1; then
    getent ahostsv4 "${host}" | awk '{print $1}' | sort -u | paste -sd'|' -
  else
    printf "n/a"
  fi
}

probe_once() {
  local ts headers body result http_code total_time remote_ip served_by resolved
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  headers="$(mktemp)"
  body="$(mktemp)"
  trap 'rm -f "${headers}" "${body}"' RETURN

  result="$(curl -ksS -o "${body}" -D "${headers}" \
    --max-time 10 \
    --connect-timeout 5 \
    -w '%{http_code}|%{time_total}|%{remote_ip}' \
    "${URL}" || true)"

  http_code="${result%%|*}"
  result="${result#*|}"
  total_time="${result%%|*}"
  remote_ip="${result##*|}"
  served_by="$(awk -F': ' 'tolower($1)=="x-served-by" {gsub("\r","",$2); print $2}' "${headers}" | tail -n1)"
  resolved="$(resolve_target "${URL}")"

  if [[ -z "${served_by}" ]]; then
    served_by="unknown"
  fi

  # echo "DEBUG: ${http_code}|${total_time}|${remote_ip}|${served_by}"

  printf '%s,%s,%s,%s,%s,%s\n' \
    "${ts}" \
    "${http_code}" \
    "$(python3 - <<'PY' "$total_time"
import sys
print(int(float(sys.argv[1]) * 1000))
PY
)" \
    "${remote_ip}" \
    "${served_by}" \
    "${resolved}" | tee -a "${LOG_FILE}"

  if [[ "${http_code}" == "200" ]]; then
    printf '%s[%s] %s -> %sms via %s (%s)%s\n' \
      "${GREEN}" "${ts}" "${URL}" \
      "$(python3 - <<'PY' "$total_time"
import sys
print(int(float(sys.argv[1]) * 1000))
PY
)" \
      "${remote_ip}" \
      "${served_by}" \
      "${RESET}"
  else
    printf '%s[%s] %s -> status %s via %s (%s)%s\n' \
      "${YELLOW}" "${ts}" "${URL}" "${http_code}" "${remote_ip}" "${served_by}" "${RESET}"
  fi
}

iteration=0
while true; do
  probe_once
  iteration=$((iteration + 1))

  if [[ "${COUNT}" -gt 0 && "${iteration}" -ge "${COUNT}" ]]; then
    break
  fi

  sleep "${INTERVAL}"
done
