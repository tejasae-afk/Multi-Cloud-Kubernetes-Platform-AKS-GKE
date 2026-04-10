#!/usr/bin/env bash
set -euo pipefail

PUBLIC_HOST="${PUBLIC_HOST:-}"
EXPECTED_GKE="${EXPECTED_GKE:-70}"
EXPECTED_AKS="${EXPECTED_AKS:-30}"
TOLERANCE="${TOLERANCE:-20}"
REQUESTS="${REQUESTS:-100}"

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") --public-host <host> [--requests 100] [--tolerance 20]
USAGE
}

while (($#)); do
  case "$1" in
    --public-host)
      PUBLIC_HOST="$2"
      shift 2
      ;;
    --requests)
      REQUESTS="$2"
      shift 2
      ;;
    --tolerance)
      TOLERANCE="$2"
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

output="$(./routing/scripts/traffic-split-test.sh --public-host "$PUBLIC_HOST" --requests "$REQUESTS")"
echo "$output"

result_line="$(grep '^RESULT ' <<<"$output")"
[[ -n "$result_line" ]] || { echo "missing RESULT line" >&2; exit 1; }

gke_pct="$(sed -E 's/.*gke_pct=([0-9.]+).*//' <<<"$result_line")"
aks_pct="$(sed -E 's/.*aks_pct=([0-9.]+).*//' <<<"$result_line")"

within_tolerance() {
  local expected="$1"
  local actual="$2"
  awk -v expected="$expected" -v actual="$actual" -v tolerance="$TOLERANCE" 'BEGIN { diff = actual - expected; if (diff < 0) diff = -diff; exit(diff <= tolerance ? 0 : 1) }'
}

within_tolerance "$EXPECTED_GKE" "$gke_pct" || { echo "GKE share ${gke_pct}% was outside the tolerance window" >&2; exit 1; }
within_tolerance "$EXPECTED_AKS" "$aks_pct" || { echo "AKS share ${aks_pct}% was outside the tolerance window" >&2; exit 1; }

echo "mesh routing distribution looked close enough"
