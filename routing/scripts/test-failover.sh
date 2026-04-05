#!/usr/bin/env bash
set -euo pipefail

SHARED_URL="${SHARED_URL:-https://api.platform.haleops.net/api/health}"
GKE_HOST="${GKE_HOST:-gke-api.platform.haleops.net}"
AKS_HOST="${AKS_HOST:-aks-api.platform.haleops.net}"
GKE_CONTEXT="${GKE_CONTEXT:-gke}"
AKS_CONTEXT="${AKS_CONTEXT:-aks}"
INGRESS_NAMESPACE="${INGRESS_NAMESPACE:-istio-system}"
INGRESS_DEPLOYMENT="${INGRESS_DEPLOYMENT:-istio-ingressgateway}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-240}"
POLL_SECONDS="${POLL_SECONDS:-10}"

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

for cmd in kubectl curl dig python3; do
  need_cmd "${cmd}"
done

log() {
  printf '%s[%s]%s %s\n' "${BLUE}" "$(date +"%H:%M:%S")" "${RESET}" "$*"
}

ok() {
  printf '%s[%s]%s %s\n' "${GREEN}" "$(date +"%H:%M:%S")" "${RESET}" "$*"
}

warn() {
  printf '%s[%s]%s %s\n' "${YELLOW}" "$(date +"%H:%M:%S")" "${RESET}" "$*"
}

die() {
  printf '%s[%s]%s %s\n' "${RED}" "$(date +"%H:%M:%S")" "${RESET}" "$*" >&2
  exit 1
}

http_ok() {
  local host="$1"
  local code
  code="$(curl -ksS -o /dev/null -w '%{http_code}' "https://${host}/healthz" || true)"
  [[ "${code}" == "200" ]]
}

cluster_ips() {
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
    return 0
  fi

  if contains_ip "${remote_ip}" "${AKS_IPS[@]}"; then
    printf 'aks'
    return 0
  fi

  printf 'unknown'
}

majority_target() {
  local loops="${1:-5}"
  local gke=0
  local aks=0
  local unknown=0
  local target

  for _ in $(seq 1 "${loops}"); do
    target="$(detect_target)"
    case "${target}" in
      gke) gke=$((gke + 1)) ;;
      aks) aks=$((aks + 1)) ;;
      *) unknown=$((unknown + 1)) ;;
    esac
    sleep 1
  done

  if [[ "${aks}" -gt 0 && "${gke}" -eq 0 && "${unknown}" -eq 0 ]]; then
    printf 'aks-only'
    return 0
  fi

  if [[ "${gke}" -gt 0 && "${aks}" -gt 0 ]]; then
    printf 'mixed'
    return 0
  fi

  if [[ "${gke}" -gt 0 && "${aks}" -eq 0 && "${unknown}" -eq 0 ]]; then
    printf 'gke-only'
    return 0
  fi

  printf 'unclear'
}

original_replicas="$(kubectl --context "${GKE_CONTEXT}" -n "${INGRESS_NAMESPACE}" get deploy "${INGRESS_DEPLOYMENT}" -o jsonpath='{.spec.replicas}')"

restore_ingress() {
  log "Restoring ${GKE_CONTEXT}/${INGRESS_NAMESPACE}/${INGRESS_DEPLOYMENT} to ${original_replicas} replicas"
  kubectl --context "${GKE_CONTEXT}" -n "${INGRESS_NAMESPACE}" scale deploy "${INGRESS_DEPLOYMENT}" --replicas="${original_replicas}" >/dev/null
  kubectl --context "${GKE_CONTEXT}" -n "${INGRESS_NAMESPACE}" rollout status deploy "${INGRESS_DEPLOYMENT}" --timeout=5m >/dev/null || true
}

trap restore_ingress EXIT

mapfile -t GKE_IPS < <(cluster_ips "${GKE_HOST}")
mapfile -t AKS_IPS < <(cluster_ips "${AKS_HOST}")

[[ "${#GKE_IPS[@]}" -gt 0 ]] || die "No IPs resolved for ${GKE_HOST}"
[[ "${#AKS_IPS[@]}" -gt 0 ]] || die "No IPs resolved for ${AKS_HOST}"

log "Checking both cluster-specific hosts"
http_ok "${GKE_HOST}" || die "GKE host is not healthy before failover test"
http_ok "${AKS_HOST}" || die "AKS host is not healthy before failover test"
ok "Both cluster hosts are healthy"

baseline="$(majority_target 20)"
if [[ "${baseline}" != "mixed" && "${baseline}" != "gke-only" ]]; then
  warn "Baseline wasn't nicely mixed. Carrying on anyway because DNS weighting is probabilistic."
else
  ok "Baseline traffic is healthy"
fi

log "Scaling down ${INGRESS_DEPLOYMENT} on ${GKE_CONTEXT}"
kubectl --context "${GKE_CONTEXT}" -n "${INGRESS_NAMESPACE}" scale deploy "${INGRESS_DEPLOYMENT}" --replicas=0 >/dev/null
kubectl --context "${GKE_CONTEXT}" -n "${INGRESS_NAMESPACE}" rollout status deploy "${INGRESS_DEPLOYMENT}" --timeout=3m >/dev/null || true

start_epoch="$(date +%s)"
while true; do
  state="$(majority_target 5)"
  now_epoch="$(date +%s)"
  elapsed=$((now_epoch - start_epoch))

  if [[ "${state}" == "aks-only" ]]; then
    ok "Traffic failed over to AKS only after ${elapsed}s"
    break
  fi

  if [[ "${elapsed}" -ge "${TIMEOUT_SECONDS}" ]]; then
    die "Timed out waiting for Traffic Manager to stop handing out GKE"
  fi

  warn "Still waiting for AKS-only responses. Current state: ${state}"
  sleep "${POLL_SECONDS}"
done

log "Bringing GKE ingress back"
restore_ingress

start_epoch="$(date +%s)"
while true; do
  state="$(majority_target 20)"
  now_epoch="$(date +%s)"
  elapsed=$((now_epoch - start_epoch))

  if [[ "${state}" == "mixed" || "${state}" == "gke-only" ]]; then
    ok "Traffic rebalanced after ${elapsed}s"
    break
  fi

  if [[ "${elapsed}" -ge "${TIMEOUT_SECONDS}" ]]; then
    die "Timed out waiting for GKE to rejoin rotation"
  fi

  warn "Still waiting for GKE to reappear. Current state: ${state}"
  sleep "${POLL_SECONDS}"
done

ok "Failover test finished cleanly"
