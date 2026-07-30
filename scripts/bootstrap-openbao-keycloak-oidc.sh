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
OIDC_AUTH_PATH="${OPENBAO_OIDC_AUTH_PATH:-oidc}"
OIDC_ROLE="${OPENBAO_OIDC_ROLE:-admin}"
OIDC_POLICY="${OPENBAO_OIDC_POLICY:-admin}"
OIDC_CLIENT_SECRET_PATH="${KEYCLOAK_OPENBAO_CLIENT_SECRET_PATH:-platform/keycloak/clients/openbao}"
OIDC_ISSUER="${OPENBAO_OIDC_ISSUER:-https://auth.lab.example.com/realms/master}"
OPENBAO_PUBLIC_URL="${OPENBAO_PUBLIC_URL:-https://bao.lab.example.com}"
KEYCLOAK_FIRST_ADMIN_EMAIL="${KEYCLOAK_FIRST_ADMIN_EMAIL:-}"

if [[ -z "${KEYCLOAK_FIRST_ADMIN_EMAIL}" ]]; then
  echo "KEYCLOAK_FIRST_ADMIN_EMAIL must be set in ${ENV_FILE}." >&2
  exit 1
fi

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

root_token="$(jq -r '.root_token' "${OPENBAO_INIT_FILE}")"
if [[ -z "${root_token}" || "${root_token}" == "null" ]]; then
  echo "Could not read root_token from ${OPENBAO_INIT_FILE}" >&2
  exit 1
fi

bao() {
  kubectl --kubeconfig "${KUBECONFIG_PATH}" -n "${OPENBAO_NAMESPACE}" exec "${OPENBAO_POD}" -- \
    env BAO_TOKEN="${root_token}" "$@"
}

client_secret="$(bao bao kv get -format=json "${KV_PATH}/${OIDC_CLIENT_SECRET_PATH}" | jq -r '.data.data.client_secret')"
if [[ -z "${client_secret}" || "${client_secret}" == "null" ]]; then
  echo "Could not read OpenBao OIDC client secret from ${KV_PATH}/${OIDC_CLIENT_SECRET_PATH}" >&2
  exit 1
fi

echo "Ensuring OpenBao OIDC auth method exists at ${OIDC_AUTH_PATH}/"
if ! bao bao auth list -format=json | jq -e --arg path "${OIDC_AUTH_PATH}/" 'has($path)' >/dev/null; then
  bao bao auth enable -path="${OIDC_AUTH_PATH}" oidc >/dev/null
fi

echo "Writing OpenBao admin policy ${OIDC_POLICY}"
policy_file="$(mktemp)"
cat >"${policy_file}" <<EOF
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo", "patch"]
}
EOF
kubectl --kubeconfig "${KUBECONFIG_PATH}" -n "${OPENBAO_NAMESPACE}" exec -i "${OPENBAO_POD}" -- \
  env BAO_TOKEN="${root_token}" bao policy write "${OIDC_POLICY}" - <"${policy_file}" >/dev/null
rm -f "${policy_file}"

echo "Configuring OpenBao OIDC client"
bao bao write "auth/${OIDC_AUTH_PATH}/config" \
  oidc_discovery_url="${OIDC_ISSUER}" \
  oidc_client_id="openbao" \
  oidc_client_secret="${client_secret}" \
  default_role="${OIDC_ROLE}" >/dev/null

echo "Writing OpenBao OIDC role ${OIDC_ROLE}"
role_file="$(mktemp)"
jq -n \
  --arg role_type "oidc" \
  --arg user_claim "email" \
  --arg email "${KEYCLOAK_FIRST_ADMIN_EMAIL}" \
  --arg ui_redirect "${OPENBAO_PUBLIC_URL}/ui/vault/auth/${OIDC_AUTH_PATH}/oidc/callback" \
  --arg cli_redirect "http://localhost:8250/oidc/callback" \
  --arg policy "${OIDC_POLICY}" \
  --arg ttl "1h" \
  '{
    role_type: $role_type,
    user_claim: $user_claim,
    bound_claims: {email: $email},
    allowed_redirect_uris: [$ui_redirect, $cli_redirect],
    oidc_scopes: ["openid", "email", "profile"],
    policies: [$policy],
    ttl: $ttl
  }' >"${role_file}"

kubectl --kubeconfig "${KUBECONFIG_PATH}" -n "${OPENBAO_NAMESPACE}" exec -i "${OPENBAO_POD}" -- \
  env BAO_TOKEN="${root_token}" bao write "auth/${OIDC_AUTH_PATH}/role/${OIDC_ROLE}" - <"${role_file}" >/dev/null
rm -f "${role_file}"

echo "OpenBao OIDC login is configured for ${KEYCLOAK_FIRST_ADMIN_EMAIL}."
