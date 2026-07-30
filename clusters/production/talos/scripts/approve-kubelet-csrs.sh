#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
kubeconfig="$root_dir/clusters/production/talos/generated/kubeconfig"

kubectl --kubeconfig "$kubeconfig" get csr -o json |
  jq -r '
    .items[]
    | select(.spec.signerName == "kubernetes.io/kubelet-serving")
    | select((.status.conditions // [] | map(.type) | index("Approved")) | not)
    | .metadata.name
  ' |
  xargs -r kubectl --kubeconfig "$kubeconfig" certificate approve
