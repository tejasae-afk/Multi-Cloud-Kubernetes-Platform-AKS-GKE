#!/usr/bin/env bash
set -euo pipefail

HOST="${HOST:-}"
SCHEME="${SCHEME:-https}"
PATH_VALUE="${PATH_VALUE:-/healthz}"
COUNT="${COUNT:-0}"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-30}"
OUTPUT_FILE="${OUTPUT_FILE:-routing/health-checks/synthetic-monitor.log}"
CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-5}"
MAX_TIME="${MAX_TIME:-10}"

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") --host <hostname> [--scheme http|https] [--path /healthz] [--count N] [--interval 30] [--output file]

Notes:
  count=0 means run forever.
USAGE
}

while (($#)); do
  case "$1" in
    --host)
      HOST="$2"
      shift 2
      ;;
    --scheme)
      SCHEME="$2"
      shift 2
      ;;
    --path)
      PATH_VALUE="$2"
      shift 2
      ;;
    --count)
      COUNT="$2"
      shift 2
      ;;
    --interval)
      INTERVAL_SECONDS="$2"
      shift 2
      ;;
    --output)
      OUTPUT_FILE="$2"
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

[[ -n "$HOST" ]] || { echo "--host is required" >&2; exit 1; }
mkdir -p "$(dirname "$OUTPUT_FILE")"

if [[ ! -f "$OUTPUT_FILE" ]]; then
  echo "timestamp,host,resolved,status_code,latency_ms,served_by" >> "$OUTPUT_FILE"
fi

run_once() {
  local timestamp resolved headers body metrics status_code latency served_by
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  resolved="$(dig +short "$HOST" | paste -sd ';' -)"
  headers="$(mktemp)"
  body="$(mktemp)"

  metrics="$(curl -sS -D "$headers" -o "$body" -w '%{http_code} %{time_total}' \
    --connect-timeout "$CONNECT_TIMEOUT" \
    --max-time "$MAX_TIME" \
    "${SCHEME}://${HOST}${PATH_VALUE}" || true)"

  status_code="$(awk '{print $1}' <<<"$metrics")"
  latency="$(awk '{print $2 * 1000}' <<<"$metrics" 2>/dev/null || echo 0)"
  served_by="$(awk -F': ' 'tolower($1)=="x-served-by" {print $2}' "$headers" | tr -d '\r' | tail -n1)"

  if [[ -z "$served_by" ]]; then
    served_by="unknown"
  fi

  printf '%s,%s,%s,%s,%s,%s\n' "$timestamp" "$HOST" "$resolved" "$status_code" "$latency" "$served_by" | tee -a "$OUTPUT_FILE"
  # echo "debug: $(cat "$headers")"

  rm -f "$headers" "$body"
}

iteration=0
while true; do
  run_once
  iteration=$((iteration + 1))
  if (( COUNT > 0 && iteration >= COUNT )); then
    break
  fi
  sleep "$INTERVAL_SECONDS"
done