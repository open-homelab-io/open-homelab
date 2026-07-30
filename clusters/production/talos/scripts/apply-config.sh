#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
talos_dir="$root_dir/clusters/production/talos"
config_file="$talos_dir/config.yaml"
generated_dir="$talos_dir/generated"

if [[ ! -f "$generated_dir/talosconfig" ]]; then
  "$talos_dir/scripts/generate-config.sh"
fi

yq -o=json -I=0 '.nodes[]' "$config_file" | while read -r node; do
  name="$(jq -r '.name' <<<"$node")"
  address="$(jq -r '.address' <<<"$node")"
  maintenance_address="$(jq -r '.maintenanceAddress // empty' <<<"$node")"
  target_address="$address"
  auth_args=(--talosconfig "$generated_dir/talosconfig" --endpoints "$address")

  if nc -G 2 -z "$address" 50000 >/dev/null 2>&1; then
    target_address="$address"
  elif [[ -n "$maintenance_address" ]] && nc -G 2 -z "$maintenance_address" 50000 >/dev/null 2>&1; then
    target_address="$maintenance_address"
    auth_args=(--insecure)
  fi

  echo "Applying $name via $target_address"
  talosctl apply-config "${auth_args[@]}" \
    --nodes "$target_address" \
    --file "$generated_dir/nodes/$name.yaml"
done
