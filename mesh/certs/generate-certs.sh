#!/usr/bin/env bash
#
# Usage:
#   ./mesh/certs/generate-certs.sh
#   ./mesh/certs/generate-certs.sh --force
#   ./mesh/certs/generate-certs.sh --output-dir ./mesh/certs/output
#
# This builds one offline root CA plus one intermediate CA per cluster.
# I only commit the directory skeleton. The generated certs stay under
# mesh/certs/output/ and that path stays out of git.
#
# The output layout looks like this:
#   output/
#     root/
#       root-cert.pem
#       root-key.pem
#     cluster1/
#       ca-cert.pem
#       ca-key.pem
#       cert-chain.pem
#       root-cert.pem
#     cluster2/
#       ca-cert.pem
#       ca-key.pem
#       cert-chain.pem
#       root-cert.pem

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/output"
FORCE="false"

while (($#)); do
  case "$1" in
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --force)
      FORCE="true"
      shift
      ;;
    -h|--help)
      sed -n '1,28p' "$0"
      exit 0
      ;;
    *)
      echo "unknown flag: $1" >&2
      exit 1
      ;;
  esac
done

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

need_cmd openssl
need_cmd mkdir
need_cmd rm
need_cmd cp
need_cmd cat
need_cmd mktemp

if [[ -d "$OUTPUT_DIR" ]] && [[ "$FORCE" != "true" ]] && find "$OUTPUT_DIR" -mindepth 1 ! -name '.gitkeep' -print -quit | grep -q .; then
  echo "${OUTPUT_DIR} already has files. rerun with --force if you really want to replace them." >&2
  exit 1
fi

umask 077
rm -rf "$OUTPUT_DIR/root" "$OUTPUT_DIR/cluster1" "$OUTPUT_DIR/cluster2"
mkdir -p "$OUTPUT_DIR/root" "$OUTPUT_DIR/cluster1" "$OUTPUT_DIR/cluster2"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

ROOT_CFG="$TMP_DIR/root-openssl.cnf"
cat > "$ROOT_CFG" <<'ROOTCFG'
[ req ]
default_bits       = 4096
prompt             = no
default_md         = sha256
distinguished_name = dn
x509_extensions    = v3_ca

[ dn ]
CN = Multi Cloud Root CA
O  = multi-cloud-k8s-platform

[ v3_ca ]
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints       = critical, CA:true, pathlen:1
keyUsage               = critical, keyCertSign, cRLSign
ROOTCFG

INTERMEDIATE_CFG="$TMP_DIR/intermediate-openssl.cnf"
cat > "$INTERMEDIATE_CFG" <<'INTCFG'
[ req ]
default_bits       = 4096
prompt             = no
default_md         = sha256
distinguished_name = dn
req_extensions     = v3_req

[ dn ]
CN = REPLACE_ME
O  = multi-cloud-k8s-platform

[ v3_req ]
basicConstraints = critical, CA:true, pathlen:0
keyUsage         = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash

[ v3_intermediate_ca ]
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid,issuer
basicConstraints       = critical, CA:true, pathlen:0
keyUsage               = critical, keyCertSign, cRLSign
INTCFG

ROOT_KEY="$OUTPUT_DIR/root/root-key.pem"
ROOT_CERT="$OUTPUT_DIR/root/root-cert.pem"

openssl genrsa -out "$ROOT_KEY" 4096 >/dev/null 2>&1
openssl req -x509 -new -nodes -key "$ROOT_KEY" -sha256 -days 3650 -out "$ROOT_CERT" -config "$ROOT_CFG" >/dev/null 2>&1

make_intermediate() {
  local cluster_name="$1"
  local target_dir="$OUTPUT_DIR/$cluster_name"
  local cfg_copy="$TMP_DIR/${cluster_name}.cnf"
  local key_file="$target_dir/ca-key.pem"
  local csr_file="$TMP_DIR/${cluster_name}.csr"
  local cert_file="$target_dir/ca-cert.pem"
  local chain_file="$target_dir/cert-chain.pem"
  local root_copy="$target_dir/root-cert.pem"

  sed "s/REPLACE_ME/${cluster_name^} Intermediate CA/" "$INTERMEDIATE_CFG" > "$cfg_copy"

  openssl genrsa -out "$key_file" 4096 >/dev/null 2>&1
  openssl req -new -key "$key_file" -out "$csr_file" -config "$cfg_copy" >/dev/null 2>&1
  openssl x509 -req \
    -in "$csr_file" \
    -CA "$ROOT_CERT" \
    -CAkey "$ROOT_KEY" \
    -CAcreateserial \
    -out "$cert_file" \
    -days 1825 \
    -sha256 \
    -extfile "$cfg_copy" \
    -extensions v3_intermediate_ca >/dev/null 2>&1

  cp "$ROOT_CERT" "$root_copy"
  cat "$cert_file" "$root_copy" > "$chain_file"
}

make_intermediate cluster1
make_intermediate cluster2

printf '\ncreated certs under %s\n\n' "$OUTPUT_DIR"
printf 'next step:\n'
printf '  kubectl --context <gke-context> create secret generic cacerts -n istio-system \\\n'
printf '    --from-file=ca-cert.pem=%s/cluster1/ca-cert.pem \\\n' "$OUTPUT_DIR"
printf '    --from-file=ca-key.pem=%s/cluster1/ca-key.pem \\\n' "$OUTPUT_DIR"
printf '    --from-file=root-cert.pem=%s/cluster1/root-cert.pem \\\n' "$OUTPUT_DIR"
printf '    --from-file=cert-chain.pem=%s/cluster1/cert-chain.pem\n' "$OUTPUT_DIR"
printf '\n'
printf '  kubectl --context <aks-context> create secret generic cacerts -n istio-system \\\n'
printf '    --from-file=ca-cert.pem=%s/cluster2/ca-cert.pem \\\n' "$OUTPUT_DIR"
printf '    --from-file=ca-key.pem=%s/cluster2/ca-key.pem \\\n' "$OUTPUT_DIR"
printf '    --from-file=root-cert.pem=%s/cluster2/root-cert.pem \\\n' "$OUTPUT_DIR"
printf '    --from-file=cert-chain.pem=%s/cluster2/cert-chain.pem\n' "$OUTPUT_DIR"

# TODO: swap this for step-ca or Vault if I ever keep the root online.
# openssl x509 -in "$ROOT_CERT" -text -noout
