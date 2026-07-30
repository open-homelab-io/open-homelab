#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${ENV_FILE:-.env}"
OUT_DIR="${IAM_ROLES_ANYWHERE_PKI_DIR:-.context/iam-roles-anywhere}"
CA_CN="${IAM_ROLES_ANYWHERE_CA_CN:-open-homelab-rolesanywhere-ca}"
CLIENT_CN="${IAM_ROLES_ANYWHERE_CLIENT_CN:-open-homelab-dns-automation}"
CA_DAYS="${IAM_ROLES_ANYWHERE_CA_DAYS:-3650}"
CLIENT_DAYS="${IAM_ROLES_ANYWHERE_CLIENT_DAYS:-365}"
ROTATE="${ROTATE:-0}"

if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
  OUT_DIR="${IAM_ROLES_ANYWHERE_PKI_DIR:-${OUT_DIR}}"
  CA_CN="${IAM_ROLES_ANYWHERE_CA_CN:-${CA_CN}}"
  CLIENT_CN="${IAM_ROLES_ANYWHERE_CLIENT_CN:-${CLIENT_CN}}"
  CA_DAYS="${IAM_ROLES_ANYWHERE_CA_DAYS:-${CA_DAYS}}"
  CLIENT_DAYS="${IAM_ROLES_ANYWHERE_CLIENT_DAYS:-${CLIENT_DAYS}}"
fi

mkdir -p "${OUT_DIR}"
chmod 700 "${OUT_DIR}"

ca_key="${OUT_DIR}/ca.key"
ca_cert="${OUT_DIR}/ca.crt"
client_key="${OUT_DIR}/dns.key"
client_csr="${OUT_DIR}/dns.csr"
client_cert="${OUT_DIR}/dns.crt"
client_ext="${OUT_DIR}/dns.ext"

if [[ "${ROTATE}" == "1" ]]; then
  rm -f "${client_key}" "${client_csr}" "${client_cert}" "${client_ext}"
fi

if [[ ! -f "${ca_key}" || ! -f "${ca_cert}" ]]; then
  openssl genrsa -out "${ca_key}" 4096 >/dev/null 2>&1
  chmod 600 "${ca_key}"
  openssl req -x509 -new -nodes \
    -key "${ca_key}" \
    -sha256 \
    -days "${CA_DAYS}" \
    -subj "/CN=${CA_CN}" \
    -out "${ca_cert}" \
    -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" >/dev/null 2>&1
fi

if [[ ! -f "${client_key}" || ! -f "${client_cert}" ]]; then
  openssl genrsa -out "${client_key}" 4096 >/dev/null 2>&1
  chmod 600 "${client_key}"
  openssl req -new \
    -key "${client_key}" \
    -subj "/CN=${CLIENT_CN}" \
    -out "${client_csr}" >/dev/null 2>&1

  cat >"${client_ext}" <<EOF
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
extendedKeyUsage=clientAuth
subjectAltName=DNS:${CLIENT_CN}
EOF

  openssl x509 -req \
    -in "${client_csr}" \
    -CA "${ca_cert}" \
    -CAkey "${ca_key}" \
    -CAcreateserial \
    -out "${client_cert}" \
    -days "${CLIENT_DAYS}" \
    -sha256 \
    -extfile "${client_ext}" >/dev/null 2>&1
fi

chmod 644 "${ca_cert}" "${client_cert}"

cat <<EOF
IAM Roles Anywhere PKI is ready.

CA certificate: ${ca_cert}
Client certificate: ${client_cert}
Client key: ${client_key}

Next:
  cd infra/aws && AWS_DNS_AUTOMATION_ENABLED=1 bun run deploy open-homelab-dns-automation && cd ../..
  scripts/bootstrap-rolesanywhere-dns.sh
EOF
