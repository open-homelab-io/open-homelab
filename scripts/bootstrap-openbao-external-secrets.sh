#!/usr/bin/env bash
set -euo pipefail

KUBECONFIG_PATH="${KUBECONFIG:-clusters/production/talos/generated/kubeconfig}"
OPENBAO_NAMESPACE="${OPENBAO_NAMESPACE:-openbao}"
OPENBAO_POD="${OPENBAO_POD:-openbao-0}"
OPENBAO_INIT_FILE="${OPENBAO_INIT_FILE:-.context/openbao/init.json}"
KUBERNETES_AUTH_PATH="${OPENBAO_KUBERNETES_AUTH_PATH:-kubernetes}"
KV_PATH="${OPENBAO_KV_PATH:-secret}"
ESO_ROLE="${OPENBAO_ESO_ROLE:-external-secrets}"
ESO_POLICY="${OPENBAO_ESO_POLICY:-external-secrets}"
ESO_SERVICE_ACCOUNT="${ESO_SERVICE_ACCOUNT:-external-secrets}"
ESO_NAMESPACE="${ESO_NAMESPACE:-external-secrets}"
ESO_AUDIENCE="${ESO_AUDIENCE:-vault}"

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

bao_sh() {
  kubectl --kubeconfig "${KUBECONFIG_PATH}" -n "${OPENBAO_NAMESPACE}" exec "${OPENBAO_POD}" -- \
    env BAO_TOKEN="${root_token}" sh -c "$1"
}

echo "Ensuring KV v2 secrets engine exists at ${KV_PATH}/"
if ! bao bao secrets list -format=json | jq -e --arg path "${KV_PATH}/" 'has($path)' >/dev/null; then
  bao bao secrets enable -path="${KV_PATH}" kv-v2 >/dev/null
fi

echo "Ensuring Kubernetes auth method exists at ${KUBERNETES_AUTH_PATH}/"
if ! bao bao auth list -format=json | jq -e --arg path "${KUBERNETES_AUTH_PATH}/" 'has($path)' >/dev/null; then
  bao bao auth enable -path="${KUBERNETES_AUTH_PATH}" kubernetes >/dev/null
fi

echo "Configuring Kubernetes auth token reviewer"
bao_sh "bao write auth/${KUBERNETES_AUTH_PATH}/config \
  token_reviewer_jwt=\"\$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)\" \
  kubernetes_host=\"https://kubernetes.default.svc\" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt" >/dev/null

policy_file="$(mktemp)"
cat >"${policy_file}" <<EOF
path "${KV_PATH}/data/*" {
  capabilities = ["read"]
}

path "${KV_PATH}/metadata/*" {
  capabilities = ["read", "list"]
}
EOF

echo "Writing OpenBao policy ${ESO_POLICY}"
kubectl --kubeconfig "${KUBECONFIG_PATH}" -n "${OPENBAO_NAMESPACE}" exec -i "${OPENBAO_POD}" -- \
  env BAO_TOKEN="${root_token}" bao policy write "${ESO_POLICY}" - <"${policy_file}" >/dev/null
rm -f "${policy_file}"

echo "Writing OpenBao Kubernetes role ${ESO_ROLE}"
bao bao write "auth/${KUBERNETES_AUTH_PATH}/role/${ESO_ROLE}" \
  "bound_service_account_names=${ESO_SERVICE_ACCOUNT}" \
  "bound_service_account_namespaces=${ESO_NAMESPACE}" \
  "policies=${ESO_POLICY}" \
  "ttl=1h" \
  "audience=${ESO_AUDIENCE}" >/dev/null

echo "OpenBao is configured for External Secrets Operator."

