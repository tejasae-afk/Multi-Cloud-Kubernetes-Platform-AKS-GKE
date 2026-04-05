#!/usr/bin/env bash
set -euo pipefail

TARGET_URL="${TARGET_URL:-https://api.platform.haleops.net}"
RESULTS_DIR="${RESULTS_DIR:-tests/load/results}"
SCRIPT_PATH="${SCRIPT_PATH:-tests/load/load-test.js}"

mkdir -p "${RESULTS_DIR}"

if command -v k6 >/dev/null 2>&1; then
  k6 run \
    --summary-export "${RESULTS_DIR}/summary.json" \
    -e TARGET_URL="${TARGET_URL}" \
    "${SCRIPT_PATH}" | tee "${RESULTS_DIR}/run.log"
else
  docker run --rm \
    --network host \
    -v "$PWD:/work" \
    -w /work \
    -e TARGET_URL="${TARGET_URL}" \
    grafana/k6 run \
      --summary-export "${RESULTS_DIR}/summary.json" \
      "${SCRIPT_PATH}" | tee "${RESULTS_DIR}/run.log"
fi

printf 'Load test finished. Results are in %s\n' "${RESULTS_DIR}"
