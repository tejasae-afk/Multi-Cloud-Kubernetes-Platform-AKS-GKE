#!/usr/bin/env bash
set -euo pipefail

PUBLIC_HOST="${PUBLIC_HOST:-}"
SCHEME="${SCHEME:-http}"
PATH_VALUE="${PATH_VALUE:-/api/health}"
REQUESTS="${REQUESTS:-200}"
SLEEP_BETWEEN="${SLEEP_BETWEEN:-0}"

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") --public-host <host> [--scheme http|https] [--path /api/health] [--requests 200]

Notes:
  The script expects deploy.yml to have already stamped x-served-by on the response.
USAGE
}

while (($#)); do
  case "$1" in
    --public-host)
      PUBLIC_HOST="$2"
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
    --requests)
      REQUESTS="$2"
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

[[ -n "$PUBLIC_HOST" ]] || { echo "--public-host is required" >&2; exit 1; }

gke_count=0
aks_count=0
other_count=0

for ((i=1; i<=REQUESTS; i++)); do
  headers="$(mktemp)"
  status_code="$(curl -sS -D "$headers" -o /dev/null -w '%{http_code}' "${SCHEME}://${PUBLIC_HOST}${PATH_VALUE}")"
  if [[ "$status_code" != "200" ]]; then
    echo "request $i returned status $status_code" >&2
    rm -f "$headers"
    exit 1
  fi

  served_by="$(awk -F': ' 'tolower($1)=="x-served-by" {print $2}' "$headers" | tr -d '' | tail -n1)"
  case "$served_by" in
    gke)
      gke_count=$((gke_count + 1))
      ;;
    aks)
      aks_count=$((aks_count + 1))
      ;;
    *)
      other_count=$((other_count + 1))
      ;;
  esac

  rm -f "$headers"
  if (( SLEEP_BETWEEN > 0 )); then
    sleep "$SLEEP_BETWEEN"
  fi
done

percent() {
  local value="$1"
  awk -v v="$value" -v total="$REQUESTS" 'BEGIN { printf "%.1f", (v / total) * 100 }'
}

gke_pct="$(percent "$gke_count")"
aks_pct="$(percent "$aks_count")"
other_pct="$(percent "$other_count")"

printf 'gke: %s (%s%%)
' "$gke_count" "$gke_pct"
printf 'aks: %s (%s%%)
' "$aks_count" "$aks_pct"
printf 'other: %s (%s%%)
' "$other_count" "$other_pct"
printf 'RESULT gke=%s aks=%s other=%s total=%s gke_pct=%s aks_pct=%s
' "$gke_count" "$aks_count" "$other_count" "$REQUESTS" "$gke_pct" "$aks_pct"

if (( other_count > REQUESTS / 4 )); then
  echo "too many responses came back without x-served-by" >&2
  exit 1
fi
