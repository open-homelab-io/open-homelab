#!/usr/bin/env bash
set -euo pipefail

command="${1:-synth}"
shift || true

env_file="../../.env"
opentofu_state_enabled="${AWS_OPENTOFU_STATE_ENABLED-}"
dns_automation_enabled="${AWS_DNS_AUTOMATION_ENABLED-}"

if [[ -f "${env_file}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${env_file}"
  set +a
fi

if [[ -n "${opentofu_state_enabled}" ]]; then
  AWS_OPENTOFU_STATE_ENABLED="${opentofu_state_enabled}"
fi

if [[ -n "${dns_automation_enabled}" ]]; then
  AWS_DNS_AUTOMATION_ENABLED="${dns_automation_enabled}"
fi

enabled() {
  case "${1:-}" in
    1 | true | TRUE | yes | YES | on | ON)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

if ! enabled "${AWS_OPENTOFU_STATE_ENABLED-}" && ! enabled "${AWS_DNS_AUTOMATION_ENABLED-}"; then
  echo "No AWS stacks enabled. Set AWS_OPENTOFU_STATE_ENABLED=1 or AWS_DNS_AUTOMATION_ENABLED=1 to run CDK."
  exit 0
fi

exec bun --env-file="${env_file}" ./node_modules/aws-cdk/bin/cdk "${command}" "$@"
