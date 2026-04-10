#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-}"
HOST_HEADER="${HOST_HEADER:-}"
INSECURE=false
RESULTS_DIR="${RESULTS_DIR:-tests/load/results}"

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") --base-url <url> [--host-header host] [--insecure]
USAGE
}

while (($#)); do
  case "$1" in
    --base-url)
      BASE_URL="$2"
      shift 2
      ;;
    --host-header)
      HOST_HEADER="$2"
      shift 2
      ;;
    --insecure)
      INSECURE=true
      shift
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

[[ -n "$BASE_URL" ]] || { echo "--base-url is required" >&2; exit 1; }
mkdir -p "$RESULTS_DIR"

summary_file="$RESULTS_DIR/summary-$(date +%Y%m%d-%H%M%S).json"
console_file="$RESULTS_DIR/console-$(date +%Y%m%d-%H%M%S).log"

run_k6() {
  BASE_URL="$BASE_URL" HOST_HEADER="$HOST_HEADER" INSECURE="$INSECURE" \
    k6 run --summary-export "$summary_file" tests/load/load-test.js | tee "$console_file"
}

if command -v k6 >/dev/null 2>&1; then
  run_k6
elif command -v docker >/dev/null 2>&1; then
  docker run --rm -i \
    -e BASE_URL="$BASE_URL" \
    -e HOST_HEADER="$HOST_HEADER" \
    -e INSECURE="$INSECURE" \
    -v "$PWD:/work" \
    -w /work \
    grafana/k6:0.49.0 run --summary-export "$summary_file" tests/load/load-test.js | tee "$console_file"
else
  echo "k6 or docker is required" >&2
  exit 1
fi

echo "results saved under $RESULTS_DIR"
