#!/usr/bin/env bash
set -euo pipefail

KUBECONFIG_PATH="${KUBECONFIG:-clusters/production/talos/generated/kubeconfig}"
NAMESPACE="${OPENBAO_NAMESPACE:-openbao}"
RELEASE_NAME="${OPENBAO_RELEASE_NAME:-openbao}"
OUT_DIR="${OPENBAO_BOOTSTRAP_DIR:-.context/openbao}"
INIT_FILE="${OPENBAO_INIT_FILE:-${OUT_DIR}/init.json}"
LEADER_ADDR="${OPENBAO_LEADER_ADDR:-http://${RELEASE_NAME}-0.${RELEASE_NAME}-internal:8200}"

if [[ ! -f "${KUBECONFIG_PATH}" ]]; then
  echo "Kubeconfig not found at ${KUBECONFIG_PATH}" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to parse OpenBao init material." >&2
  exit 1
fi

mkdir -p "${OUT_DIR}"
chmod 700 "${OUT_DIR}"

kubectl_bao() {
  local pod="$1"
  shift
  kubectl --kubeconfig "${KUBECONFIG_PATH}" -n "${NAMESPACE}" exec "${pod}" -- "$@"
}

wait_for_pod_running() {
  local pod="$1"
  echo "Waiting for ${pod} to be Running"
  for _ in {1..120}; do
    phase="$(kubectl --kubeconfig "${KUBECONFIG_PATH}" -n "${NAMESPACE}" get pod "${pod}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    if [[ "${phase}" == "Running" ]]; then
      return 0
    fi
    sleep 5
  done
  echo "${pod} did not become Running in time" >&2
  return 1
}

bao_status_json() {
  local pod="$1"
  kubectl_bao "${pod}" bao status -format=json 2>/dev/null || true
}

unseal_pod() {
  local pod="$1"
  local status
  local sealed
  status="$(bao_status_json "${pod}")"
  sealed="$(jq -r '.sealed // true' <<<"${status}")"

  if [[ "${sealed}" == "false" ]]; then
    echo "${pod} is already unsealed"
    return 0
  fi

  echo "Unsealing ${pod}"
  local threshold
  threshold="$(jq -r '.unseal_threshold' "${INIT_FILE}")"

  jq -r --argjson threshold "${threshold}" '.unseal_keys_b64[0:$threshold][]' "${INIT_FILE}" |
    while IFS= read -r key; do
      kubectl_bao "${pod}" bao operator unseal "${key}" >/dev/null
    done
}

list_peers() {
  jq -r '.root_token' "${INIT_FILE}" |
    kubectl --kubeconfig "${KUBECONFIG_PATH}" -n "${NAMESPACE}" exec -i "${RELEASE_NAME}-0" -- \
      sh -c 'read -r token; BAO_TOKEN="${token}" bao operator raft list-peers "$@"' sh "$@"
}

wait_for_voters() {
  echo "Waiting for OpenBao Raft peers to become voters"
  for _ in {1..60}; do
    peers_json="$(list_peers -format=json)"
    voter_count="$(jq '[.data.config.servers[] | select(.voter == true)] | length' <<<"${peers_json}")"
    if [[ "${voter_count}" == "3" ]]; then
      return 0
    fi
    sleep 5
  done

  echo "OpenBao Raft peers did not all become voters in time" >&2
  list_peers >&2
  return 1
}

wait_for_pod_running "${RELEASE_NAME}-0"

status="$(bao_status_json "${RELEASE_NAME}-0")"
initialized="$(jq -r '.initialized // false' <<<"${status}")"

if [[ "${initialized}" != "true" ]]; then
  if [[ -f "${INIT_FILE}" ]]; then
    echo "${INIT_FILE} already exists, but ${RELEASE_NAME}-0 is not initialized. Refusing to overwrite init material." >&2
    exit 1
  fi

  echo "Initializing ${RELEASE_NAME}-0; writing init material to ${INIT_FILE}"
  kubectl_bao "${RELEASE_NAME}-0" bao operator init -format=json >"${INIT_FILE}"
  chmod 600 "${INIT_FILE}"
elif [[ ! -f "${INIT_FILE}" ]]; then
  echo "${RELEASE_NAME}-0 is already initialized, but ${INIT_FILE} is missing. Restore the init material before unsealing." >&2
  exit 1
else
  echo "${RELEASE_NAME}-0 is already initialized"
fi

unseal_pod "${RELEASE_NAME}-0"

for ordinal in 1 2; do
  pod="${RELEASE_NAME}-${ordinal}"
  wait_for_pod_running "${pod}"

  status="$(bao_status_json "${pod}")"
  initialized="$(jq -r '.initialized // false' <<<"${status}")"

  if [[ "${initialized}" != "true" ]]; then
    echo "Joining ${pod} to Raft leader ${LEADER_ADDR}"
    kubectl_bao "${pod}" bao operator raft join "${LEADER_ADDR}" >/dev/null
  fi

  unseal_pod "${pod}"
done

echo "Waiting for OpenBao pods to become Ready"
kubectl --kubeconfig "${KUBECONFIG_PATH}" -n "${NAMESPACE}" wait \
  --for=condition=Ready pod \
  -l app.kubernetes.io/name=openbao,component=server \
  --timeout=5m

wait_for_voters

echo "OpenBao Raft peers:"
list_peers
