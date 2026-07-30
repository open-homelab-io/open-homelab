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
KEYCLOAK_DB_SECRET_PATH="${KEYCLOAK_DB_SECRET_PATH:-platform/keycloak/database}"
KEYCLOAK_ADMIN_SECRET_PATH="${KEYCLOAK_ADMIN_SECRET_PATH:-platform/keycloak/admin}"
KEYCLOAK_FIRST_ADMIN_SECRET_PATH="${KEYCLOAK_FIRST_ADMIN_SECRET_PATH:-platform/keycloak/users/first-admin}"
KEYCLOAK_ARGOCD_CLIENT_SECRET_PATH="${KEYCLOAK_ARGOCD_CLIENT_SECRET_PATH:-platform/keycloak/clients/argocd}"
KEYCLOAK_OPENBAO_CLIENT_SECRET_PATH="${KEYCLOAK_OPENBAO_CLIENT_SECRET_PATH:-platform/keycloak/clients/openbao}"
KEYCLOAK_LONGHORN_CLIENT_SECRET_PATH="${KEYCLOAK_LONGHORN_CLIENT_SECRET_PATH:-platform/keycloak/clients/longhorn}"
KEYCLOAK_GRAFANA_CLIENT_SECRET_PATH="${KEYCLOAK_GRAFANA_CLIENT_SECRET_PATH:-platform/keycloak/clients/grafana}"
KEYCLOAK_HARBOR_CLIENT_SECRET_PATH="${KEYCLOAK_HARBOR_CLIENT_SECRET_PATH:-platform/keycloak/clients/harbor}"
GRAFANA_ADMIN_SECRET_PATH="${GRAFANA_ADMIN_SECRET_PATH:-platform/grafana/admin}"
HARBOR_SECRET_PATH="${HARBOR_SECRET_PATH:-platform/harbor/core}"
LONGHORN_OAUTH2_PROXY_SECRET_PATH="${LONGHORN_OAUTH2_PROXY_SECRET_PATH:-platform/longhorn/oauth2-proxy}"
KEYCLOAK_DB_USERNAME="${KEYCLOAK_DB_USERNAME:-keycloak}"
KEYCLOAK_ADMIN_USERNAME="${KEYCLOAK_ADMIN_USERNAME:-admin}"
KEYCLOAK_FIRST_ADMIN_USERNAME="${KEYCLOAK_FIRST_ADMIN_USERNAME:-}"
KEYCLOAK_FIRST_ADMIN_EMAIL="${KEYCLOAK_FIRST_ADMIN_EMAIL:-}"
KEYCLOAK_FIRST_ADMIN_TEMP_PASSWORD="${KEYCLOAK_FIRST_ADMIN_TEMP_PASSWORD:-}"
KEYCLOAK_FIRST_ADMIN_FIRST_NAME="${KEYCLOAK_FIRST_ADMIN_FIRST_NAME:-}"
KEYCLOAK_FIRST_ADMIN_LAST_NAME="${KEYCLOAK_FIRST_ADMIN_LAST_NAME:-}"
KEYCLOAK_ROTATE_SECRETS="${KEYCLOAK_ROTATE_SECRETS:-false}"
LONGHORN_OAUTH2_PROXY_ROTATE_SECRET="${LONGHORN_OAUTH2_PROXY_ROTATE_SECRET:-false}"

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
  echo "openssl is required to generate Keycloak credentials." >&2
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

read_secret_property() {
  local path="$1"
  local property="$2"

  bao bao kv get -format=json "${KV_PATH}/${path}" 2>/dev/null \
    | jq -r --arg property "${property}" '.data.data[$property] // empty'
}

random_secret() {
  openssl rand -hex 32
}

random_secret_chars() {
  local length="$1"
  openssl rand -hex 32 | head -c "${length}"
}

random_cookie_secret() {
  openssl rand -base64 32 | tr -d '\n' | head -c 32
}

write_secret_if_needed() {
  local path="$1"
  local username="$2"
  local password="$3"

  if secret_exists "${path}" && [[ "${KEYCLOAK_ROTATE_SECRETS}" != "true" ]]; then
    echo "Keeping existing OpenBao secret at ${KV_PATH}/${path}"
    return
  fi

  bao bao kv put "${KV_PATH}/${path}" \
    "username=${username}" \
    "password=${password}" >/dev/null
  echo "Wrote OpenBao secret at ${KV_PATH}/${path}"
}

write_oidc_client_if_needed() {
  local path="$1"
  local client_id="$2"

  if secret_exists "${path}" && [[ "${KEYCLOAK_ROTATE_SECRETS}" != "true" ]]; then
    echo "Keeping existing OpenBao secret at ${KV_PATH}/${path}"
    return
  fi

  bao bao kv put "${KV_PATH}/${path}" \
    "client_id=${client_id}" \
    "client_secret=$(random_secret)" >/dev/null
  echo "Wrote OpenBao secret at ${KV_PATH}/${path}"
}

write_longhorn_oauth2_proxy_if_needed() {
  local path="$1"

  if secret_exists "${path}" && [[ "${KEYCLOAK_ROTATE_SECRETS}" != "true" && "${LONGHORN_OAUTH2_PROXY_ROTATE_SECRET}" != "true" ]]; then
    echo "Keeping existing OpenBao secret at ${KV_PATH}/${path}"
    return
  fi

  bao bao kv put "${KV_PATH}/${path}" \
    "cookie_secret=$(random_cookie_secret)" >/dev/null
  echo "Wrote OpenBao secret at ${KV_PATH}/${path}"
}

write_harbor_secret_if_needed() {
  local path="$1"

  if secret_exists "${path}" && [[ "${KEYCLOAK_ROTATE_SECRETS}" != "true" ]]; then
    echo "Keeping existing OpenBao secret at ${KV_PATH}/${path}"
    return
  fi

  bao bao kv put "${KV_PATH}/${path}" \
    "username=admin" \
    "password=$(random_secret)" \
    "db_username=harbor" \
    "db_password=$(random_secret)" \
    "secret_key=$(random_secret_chars 16)" \
    "core_secret=$(random_secret_chars 16)" \
    "csrf_key=$(random_secret_chars 32)" \
    "jobservice_secret=$(random_secret_chars 16)" \
    "registry_http_secret=$(random_secret_chars 16)" >/dev/null
  echo "Wrote OpenBao secret at ${KV_PATH}/${path}"
}

write_secret_if_needed "${KEYCLOAK_DB_SECRET_PATH}" "${KEYCLOAK_DB_USERNAME}" "$(random_secret)"
write_secret_if_needed "${KEYCLOAK_ADMIN_SECRET_PATH}" "${KEYCLOAK_ADMIN_USERNAME}" "$(random_secret)"
write_oidc_client_if_needed "${KEYCLOAK_ARGOCD_CLIENT_SECRET_PATH}" "argocd"
write_oidc_client_if_needed "${KEYCLOAK_OPENBAO_CLIENT_SECRET_PATH}" "openbao"
write_oidc_client_if_needed "${KEYCLOAK_LONGHORN_CLIENT_SECRET_PATH}" "longhorn"
write_oidc_client_if_needed "${KEYCLOAK_GRAFANA_CLIENT_SECRET_PATH}" "grafana"
write_oidc_client_if_needed "${KEYCLOAK_HARBOR_CLIENT_SECRET_PATH}" "harbor"
write_secret_if_needed "${GRAFANA_ADMIN_SECRET_PATH}" "admin" "$(random_secret)"
write_harbor_secret_if_needed "${HARBOR_SECRET_PATH}"
write_longhorn_oauth2_proxy_if_needed "${LONGHORN_OAUTH2_PROXY_SECRET_PATH}"

if [[ -n "${KEYCLOAK_FIRST_ADMIN_USERNAME}" || -n "${KEYCLOAK_FIRST_ADMIN_EMAIL}" ]]; then
  if [[ -z "${KEYCLOAK_FIRST_ADMIN_USERNAME}" || -z "${KEYCLOAK_FIRST_ADMIN_EMAIL}" ]]; then
    echo "Set both KEYCLOAK_FIRST_ADMIN_USERNAME and KEYCLOAK_FIRST_ADMIN_EMAIL, or neither." >&2
    exit 1
  fi

  first_admin_password="${KEYCLOAK_FIRST_ADMIN_TEMP_PASSWORD}"
  if [[ -z "${first_admin_password}" ]] && secret_exists "${KEYCLOAK_FIRST_ADMIN_SECRET_PATH}"; then
    first_admin_password="$(read_secret_property "${KEYCLOAK_FIRST_ADMIN_SECRET_PATH}" "temporary_password")"
  fi
  if [[ -z "${first_admin_password}" || "${KEYCLOAK_ROTATE_SECRETS}" == "true" ]]; then
    first_admin_password="$(random_secret)"
  fi

  bao bao kv put "${KV_PATH}/${KEYCLOAK_FIRST_ADMIN_SECRET_PATH}" \
    "username=${KEYCLOAK_FIRST_ADMIN_USERNAME}" \
    "email=${KEYCLOAK_FIRST_ADMIN_EMAIL}" \
    "temporary_password=${first_admin_password}" \
    "first_name=${KEYCLOAK_FIRST_ADMIN_FIRST_NAME}" \
    "last_name=${KEYCLOAK_FIRST_ADMIN_LAST_NAME}" >/dev/null
  echo "Wrote OpenBao secret at ${KV_PATH}/${KEYCLOAK_FIRST_ADMIN_SECRET_PATH}"
else
  echo "Skipping first human Keycloak admin secret; set KEYCLOAK_FIRST_ADMIN_USERNAME and KEYCLOAK_FIRST_ADMIN_EMAIL in ${ENV_FILE}."
fi

echo "Keycloak OpenBao secrets are ready for External Secrets Operator."
