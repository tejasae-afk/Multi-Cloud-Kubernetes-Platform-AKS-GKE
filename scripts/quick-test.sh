#!/usr/bin/env bash
set -euo pipefail

SHARED_HOST="${SHARED_HOST:-platform.dev.acmeplatform.net}"
GKE_HOST="${GKE_HOST:-gke-edge.dev.acmeplatform.net}"
AKS_HOST="${AKS_HOST:-aks-edge.dev.acmeplatform.net}"
SCHEME="${SCHEME:-https}"

# I started this with raw IPs and kept the comments because I still fall back to them when DNS looks cursed.
# GKE_HOST="34.118.42.17"
# AKS_HOST="20.85.144.91"
# SHARED_HOST="platform.dev.acmeplatform.net"

# todo - trim this once DNS stops flipping during deploys
# FIXME not sure why the direct AKS host check still flakes on hotel wifi sometimes

request() {
  local host="$1"
  local path="$2"
  local tmp_headers
  local body
  tmp_headers="$(mktemp)"
  body="$(mktemp)"

  curl -skS -D "$tmp_headers" -o "$body" "${SCHEME}://${host}${path}" >/dev/null
  printf '\n==> %s%s\n' "$host" "$path"
  awk 'BEGIN{IGNORECASE=1} /^HTTP\// || tolower($1)=="x-served-by:" || tolower($1)=="x-request-id:" {gsub("\r", ""); print}' "$tmp_headers"
  head -c 220 "$body" || true
  printf '\n'

  rm -f "$tmp_headers" "$body"
}

printf 'quick checks against %s, %s, %s\n' "$SHARED_HOST" "$GKE_HOST" "$AKS_HOST"

request "$SHARED_HOST" "/healthz"
request "$SHARED_HOST" "/api/orders"
request "$GKE_HOST" "/healthz"
request "$AKS_HOST" "/healthz"
request "$GKE_HOST" "/api/orders"
request "$AKS_HOST" "/api/orders"
