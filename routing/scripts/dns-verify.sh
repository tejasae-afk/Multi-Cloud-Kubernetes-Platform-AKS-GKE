#!/usr/bin/env bash
set -euo pipefail

PUBLIC_HOST="${PUBLIC_HOST:-}"
TRAFFIC_MANAGER_FQDN="${TRAFFIC_MANAGER_FQDN:-}"
GKE_EDGE_HOST="${GKE_EDGE_HOST:-}"
AKS_EDGE_HOST="${AKS_EDGE_HOST:-}"

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") --public-host <host> --traffic-manager-fqdn <fqdn> --gke-edge-host <host> --aks-edge-host <host>
USAGE
}

while (($#)); do
  case "$1" in
    --public-host)
      PUBLIC_HOST="$2"
      shift 2
      ;;
    --traffic-manager-fqdn)
      TRAFFIC_MANAGER_FQDN="$2"
      shift 2
      ;;
    --gke-edge-host)
      GKE_EDGE_HOST="$2"
      shift 2
      ;;
    --aks-edge-host)
      AKS_EDGE_HOST="$2"
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
[[ -n "$TRAFFIC_MANAGER_FQDN" ]] || { echo "--traffic-manager-fqdn is required" >&2; exit 1; }
[[ -n "$GKE_EDGE_HOST" ]] || { echo "--gke-edge-host is required" >&2; exit 1; }
[[ -n "$AKS_EDGE_HOST" ]] || { echo "--aks-edge-host is required" >&2; exit 1; }

say() {
  printf "${BLUE}==>${NC} %s\n" "$*"
}

ok() {
  printf "${GREEN}%s${NC}\n" "$*"
}

warn() {
  printf "${YELLOW}%s${NC}\n" "$*"
}

say "public host chain"
nslookup "$PUBLIC_HOST"
dig +short "$PUBLIC_HOST" CNAME || true

say "traffic manager target"
nslookup "$TRAFFIC_MANAGER_FQDN"
dig +short "$TRAFFIC_MANAGER_FQDN"

say "cluster edge records"
for host in "$GKE_EDGE_HOST" "$AKS_EDGE_HOST"; do
  echo "-- $host"
  nslookup "$host"
  dig +short "$host"
done

cname_target="$(dig +short "$PUBLIC_HOST" CNAME | head -n1 | sed 's/\.$//')"
if [[ "$cname_target" == "$TRAFFIC_MANAGER_FQDN" ]]; then
  ok "public host points at Traffic Manager"
else
  warn "public host CNAME is ${cname_target:-<empty>}"
fi

public_answers="$(dig +short "$TRAFFIC_MANAGER_FQDN" | wc -l | tr -d ' ')"
if (( public_answers >= 1 )); then
  ok "Traffic Manager is answering with at least one endpoint"
else
  printf "${RED}Traffic Manager returned no addresses${NC}\n" >&2
  exit 1
fi