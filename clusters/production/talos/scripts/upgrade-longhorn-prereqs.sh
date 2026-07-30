#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
talos_dir="$root_dir/clusters/production/talos"
config_file="$talos_dir/config.yaml"
generated_dir="$talos_dir/generated"
talosconfig="$generated_dir/talosconfig"

"$talos_dir/scripts/generate-config.sh"

if [[ ! -f "$talosconfig" ]]; then
  echo "Talos config not found at $talosconfig" >&2
  exit 1
fi

installer_image="$(yq -r '.cluster.talosInstallerImage' "$config_file")"
controlplane_ip="$(yq -r '.nodes[] | select(.role == "controlplane") | .address' "$config_file" | head -1)"
only_nodes="${ONLY_NODES:-}"

if [[ -z "$installer_image" || "$installer_image" == "null" ]]; then
  echo "cluster.talosInstallerImage is required in $config_file" >&2
  exit 1
fi

yq -o=json -I=0 '.nodes[]' "$config_file" |
  jq -sc '. | sort_by(if .role == "controlplane" then 1 else 0 end)[]' |
  while read -r node; do
  name="$(jq -r '.name' <<<"$node")"
  address="$(jq -r '.address' <<<"$node")"
  role="$(jq -r '.role' <<<"$node")"

  if [[ -n "$only_nodes" && ! " $only_nodes " =~ [[:space:]]$name[[:space:]] ]]; then
    echo "Skipping $name; not listed in ONLY_NODES"
    continue
  fi

  echo "Applying staged Longhorn prerequisite config to $name ($address)"
  talosctl --talosconfig "$talosconfig" --endpoints "$controlplane_ip" --nodes "$address" apply-config \
    --mode staged \
    --file "$generated_dir/nodes/$name.yaml"

  echo "Upgrading $name ($role) to $installer_image"
  talosctl --talosconfig "$talosconfig" --endpoints "$controlplane_ip" --nodes "$address" upgrade \
    --image "$installer_image" \
    --wait

  echo "Verifying Longhorn host tools on $name"
  talosctl --talosconfig "$talosconfig" --endpoints "$controlplane_ip" --nodes "$address" read /usr/local/sbin/iscsiadm >/dev/null
  talosctl --talosconfig "$talosconfig" --endpoints "$controlplane_ip" --nodes "$address" read /usr/local/sbin/fstrim >/dev/null
done

echo "Longhorn Talos prerequisites are installed on all nodes."
