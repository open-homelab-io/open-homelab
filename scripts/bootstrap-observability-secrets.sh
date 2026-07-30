#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${ENV_FILE:-.env}"
if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
fi

KUBECONFIG_PATH="${KUBECONFIG:-clusters/production/talos/generated/kubeconfig}"
OPENBAO_NAMESPACE="${OPENBAO_NAMESPACE:-openbao}"
OPENBAO_POD="${OPENBAO_POD:-openbao-0}"
OPENBAO_INIT_FILE="${OPENBAO_INIT_FILE:-.context/openbao/init.json}"
KV_PATH="${OPENBAO_KV_PATH:-secret}"
MIMIR_MINIO_SECRET_PATH="${MIMIR_MINIO_SECRET_PATH:-platform/observability/mimir/minio}"
OBSERVABILITY_ROTATE_SECRETS="${OBSERVABILITY_ROTATE_SECRETS:-false}"

if [[ ! -f "${KUBECONFIG_PATH}" ]]; then
  echo "Kubeconfig not found at ${KUBECONFIG_PATH}" >&2
  exit 1
fi

if [[ ! -f "${OPENBAO_INIT_FILE}" ]]; then
  echo "OpenBao init material not found at ${OPENBAO_INIT_FILE}" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to parse OpenBao init material." >&2
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl is required to generate observability credentials." >&2
  exit 1
fi

root_token="$(jq -r '.root_token' "${OPENBAO_INIT_FILE}")"
if [[ -z "${root_token}" || "${root_token}" == "null" ]]; then
  echo "Could not read root_token from ${OPENBAO_INIT_FILE}" >&2
  exit 1
fi

bao() {
  kubectl --kubeconfig "${KUBECONFIG_PATH}" -n "${OPENBAO_NAMESPACE}" exec "${OPENBAO_POD}" -- \
    env BAO_TOKEN="${root_token}" "$@"
}

secret_exists() {
  bao bao kv get -format=json "${KV_PATH}/$1" >/dev/null 2>&1
}

random_secret() {
  openssl rand -hex 32
}

write_mimir_minio_if_needed() {
  local path="$1"

  if secret_exists "${path}" && [[ "${OBSERVABILITY_ROTATE_SECRETS}" != "true" ]]; then
    echo "Keeping existing OpenBao secret at ${KV_PATH}/${path}"
    return
  fi

  bao bao kv put "${KV_PATH}/${path}" \
    "root_password=$(random_secret)" >/dev/null
  echo "Wrote OpenBao secret at ${KV_PATH}/${path}"
}

write_mimir_minio_if_needed "${MIMIR_MINIO_SECRET_PATH}"

echo "Observability OpenBao secrets are ready for External Secrets Operator."
