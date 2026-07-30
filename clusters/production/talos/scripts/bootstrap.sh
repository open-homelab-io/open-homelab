#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
talos_dir="$root_dir/clusters/production/talos"
generated_dir="$talos_dir/generated"
controlplane_ip="$(yq -r '.nodes[] | select(.role == "controlplane") | .address' "$talos_dir/config.yaml" | head -1)"

talosctl --talosconfig "$generated_dir/talosconfig" bootstrap \
  --endpoints "$controlplane_ip" \
  --nodes "$controlplane_ip"

talosctl --talosconfig "$generated_dir/talosconfig" kubeconfig "$generated_dir/kubeconfig" \
  --endpoints "$controlplane_ip" \
  --nodes "$controlplane_ip" \
  --force

echo "Kubeconfig written to $generated_dir/kubeconfig"

