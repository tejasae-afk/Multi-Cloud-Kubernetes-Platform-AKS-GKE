#!/usr/bin/env bash
set -euo pipefail

SHARED_URL="https://api.platform.haleops.net/api/health"
GKE_HOST="gke-api.platform.haleops.net"
AKS_HOST="aks-api.platform.haleops.net"
REQUESTS="${REQUESTS:-100}"
EXPECTED_GKE="${EXPECTED_GKE:-70}"
EXPECTED_AKS="${EXPECTED_AKS:-30}"
TOLERANCE="${TOLERANCE:-15}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --shared-url)
      SHARED_URL="$2"
      shift 2
      ;;
    --gke-host)
      GKE_HOST="$2"
      shift 2
      ;;
    --aks-host)
      AKS_HOST="$2"
      shift 2
      ;;
    *)
      echo "unknown flag: $1" >&2
      exit 1
      ;;
  esac
done

for cmd in curl dig python3; do
  command -v "${cmd}" >/dev/null 2>&1 || { echo "missing command: ${cmd}" >&2; exit 1; }
done

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

mapfile -t GKE_IPS < <(ips_for_host "${GKE_HOST}")
mapfile -t AKS_IPS < <(ips_for_host "${AKS_HOST}")

[[ "${#GKE_IPS[@]}" -gt 0 ]] || { echo "no GKE IPs found" >&2; exit 1; }
[[ "${#AKS_IPS[@]}" -gt 0 ]] || { echo "no AKS IPs found" >&2; exit 1; }

detect_target() {
  local headers body remote_ip served_by
  headers="$(mktemp)"
  body="$(mktemp)"
  remote_ip="$(curl -ksS -o "${body}" -D "${headers}" --max-time 10 -w '%{remote_ip}' "${SHARED_URL}" || true)"
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
  elif contains_ip "${remote_ip}" "${AKS_IPS[@]}"; then
    printf 'aks'
  else
    printf 'unknown'
  fi
}

gke=0
aks=0
unknown=0

for _ in $(seq 1 "${REQUESTS}"); do
  case "$(detect_target)" in
    gke) gke=$((gke + 1)) ;;
    aks) aks=$((aks + 1)) ;;
    *) unknown=$((unknown + 1)) ;;
  esac
done

gke_pct="$(pct "${gke}" "${REQUESTS}")"
aks_pct="$(pct "${aks}" "${REQUESTS}")"

printf 'GKE: %s (%s%%)\n' "${gke}" "${gke_pct}"
printf 'AKS: %s (%s%%)\n' "${aks}" "${aks_pct}"
printf 'Unknown: %s\n' "${unknown}"

python3 - <<'PY' "$gke_pct" "$aks_pct" "$EXPECTED_GKE" "$EXPECTED_AKS" "$TOLERANCE"
import sys
gke_pct = float(sys.argv[1])
aks_pct = float(sys.argv[2])
expected_gke = float(sys.argv[3])
expected_aks = float(sys.argv[4])
tolerance = float(sys.argv[5])

if abs(gke_pct - expected_gke) > tolerance:
    raise SystemExit(f"GKE routing drifted too far: got {gke_pct} expected {expected_gke}±{tolerance}")

if abs(aks_pct - expected_aks) > tolerance:
    raise SystemExit(f"AKS routing drifted too far: got {aks_pct} expected {expected_aks}±{tolerance}")
PY
