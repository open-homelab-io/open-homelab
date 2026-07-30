#!/usr/bin/env bash
set -euo pipefail

KUBECONFIG_PATH="${KUBECONFIG:-clusters/production/talos/generated/kubeconfig}"
ENV_FILE="${ENV_FILE:-.env}"
STACK_NAME="${IAM_ROLES_ANYWHERE_STACK_NAME:-open-homelab-dns-automation}"
AWS_REGION_VALUE="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
CLIENT_CERT_PATH="${IAM_ROLES_ANYWHERE_CLIENT_CERT_PATH:-.context/iam-roles-anywhere/dns.crt}"
CLIENT_KEY_PATH="${IAM_ROLES_ANYWHERE_CLIENT_KEY_PATH:-.context/iam-roles-anywhere/dns.key}"
DELETE_STATIC_AWS_DNS_SECRETS="${DELETE_STATIC_AWS_DNS_SECRETS:-0}"

if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
  STACK_NAME="${IAM_ROLES_ANYWHERE_STACK_NAME:-${STACK_NAME}}"
  AWS_REGION_VALUE="${AWS_REGION:-${AWS_DEFAULT_REGION:-${AWS_REGION_VALUE}}}"
  CLIENT_CERT_PATH="${IAM_ROLES_ANYWHERE_CLIENT_CERT_PATH:-${CLIENT_CERT_PATH}}"
  CLIENT_KEY_PATH="${IAM_ROLES_ANYWHERE_CLIENT_KEY_PATH:-${CLIENT_KEY_PATH}}"
  DELETE_STATIC_AWS_DNS_SECRETS="${DELETE_STATIC_AWS_DNS_SECRETS:-${DELETE_STATIC_AWS_DNS_SECRETS}}"
fi

if [[ ! -f "${KUBECONFIG_PATH}" ]]; then
  echo "Kubeconfig not found at ${KUBECONFIG_PATH}" >&2
  exit 1
fi

if [[ ! -f "${CLIENT_CERT_PATH}" || ! -f "${CLIENT_KEY_PATH}" ]]; then
  echo "Client certificate/key not found. Run scripts/bootstrap-rolesanywhere-ca.sh first." >&2
  exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI is required to read CloudFormation outputs for ${STACK_NAME}." >&2
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required to write Kubernetes config for IAM Roles Anywhere." >&2
  exit 1
fi

stack_output() {
  local output_key="$1"
  aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${AWS_REGION_VALUE}" \
    --query "Stacks[0].Outputs[?OutputKey=='${output_key}'].OutputValue | [0]" \
    --output text
}

role_arn="${IAM_ROLES_ANYWHERE_ROLE_ARN:-$(stack_output DnsAutomationRoleArn)}"
profile_arn="${IAM_ROLES_ANYWHERE_PROFILE_ARN:-$(stack_output RolesAnywhereProfileArn)}"
trust_anchor_arn="${IAM_ROLES_ANYWHERE_TRUST_ANCHOR_ARN:-$(stack_output RolesAnywhereTrustAnchorArn)}"

if [[ -z "${role_arn}" || "${role_arn}" == "None" || -z "${profile_arn}" || "${profile_arn}" == "None" || -z "${trust_anchor_arn}" || "${trust_anchor_arn}" == "None" ]]; then
  echo "Could not resolve Roles Anywhere outputs from CloudFormation stack ${STACK_NAME}." >&2
  exit 1
fi

for namespace in cert-manager external-dns; do
  KUBECONFIG="${KUBECONFIG_PATH}" kubectl create namespace "${namespace}" --dry-run=client -o yaml \
    | KUBECONFIG="${KUBECONFIG_PATH}" kubectl apply -f -

  KUBECONFIG="${KUBECONFIG_PATH}" kubectl -n "${namespace}" create configmap rolesanywhere-dns \
    --from-literal=AWS_REGION="${AWS_REGION_VALUE}" \
    --from-literal=ROLESANYWHERE_ROLE_ARN="${role_arn}" \
    --from-literal=ROLESANYWHERE_PROFILE_ARN="${profile_arn}" \
    --from-literal=ROLESANYWHERE_TRUST_ANCHOR_ARN="${trust_anchor_arn}" \
    --dry-run=client -o yaml \
    | KUBECONFIG="${KUBECONFIG_PATH}" kubectl apply -f -

  KUBECONFIG="${KUBECONFIG_PATH}" kubectl -n "${namespace}" create secret generic rolesanywhere-certificate \
    --from-file=tls.crt="${CLIENT_CERT_PATH}" \
    --from-file=tls.key="${CLIENT_KEY_PATH}" \
    --dry-run=client -o yaml \
    | KUBECONFIG="${KUBECONFIG_PATH}" kubectl apply -f -

  if [[ "${DELETE_STATIC_AWS_DNS_SECRETS}" == "1" ]]; then
    KUBECONFIG="${KUBECONFIG_PATH}" kubectl -n "${namespace}" delete secret route53-credentials --ignore-not-found
  fi
done

echo "IAM Roles Anywhere DNS credentials are configured in cert-manager and external-dns."
