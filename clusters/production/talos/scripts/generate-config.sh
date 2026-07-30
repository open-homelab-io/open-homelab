#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
talos_dir="$root_dir/clusters/production/talos"
config_file="$talos_dir/config.yaml"
generated_dir="$talos_dir/generated"
secrets_file="$talos_dir/secrets.yaml"

mkdir -p "$generated_dir/nodes"

if [[ ! -f "$secrets_file" ]]; then
  talosctl gen secrets --output-file "$secrets_file"
fi

cluster_name="$(yq -r '.cluster.name' "$config_file")"
cluster_endpoint="$(yq -r '.cluster.endpoint' "$config_file")"
dns_domain="$(yq -r '.cluster.dnsDomain' "$config_file")"
install_disk="$(yq -r '.cluster.installDisk' "$config_file")"
kubernetes_version="$(yq -r '.cluster.kubernetesVersion' "$config_file")"
talos_version="$(yq -r '.cluster.talosVersion' "$config_file")"
talos_installer_image="$(yq -r '.cluster.talosInstallerImage // "ghcr.io/siderolabs/installer:" + .cluster.talosVersion' "$config_file")"

talosctl gen config "$cluster_name" "$cluster_endpoint" \
  --with-secrets "$secrets_file" \
  --dns-domain "$dns_domain" \
  --install-disk "$install_disk" \
  --install-image "$talos_installer_image" \
  --kubernetes-version "$kubernetes_version" \
  --talos-version "$talos_version" \
  --config-patch "@$talos_dir/patches/common.yaml" \
  --config-patch-control-plane "@$talos_dir/patches/controlplane.yaml" \
  --config-patch-worker "@$talos_dir/patches/worker.yaml" \
  --output "$generated_dir/base" \
  --force

gateway="$(yq -r '.network.gateway' "$config_file")"
prefix="$(yq -r '.network.prefix' "$config_file")"
interface="$(yq -r '.network.interface' "$config_file")"

yq -o=json -I=0 '.nodes[]' "$config_file" | while read -r node; do
  name="$(jq -r '.name' <<<"$node")"
  role="$(jq -r '.role' <<<"$node")"
  address="$(jq -r '.address' <<<"$node")"
  source_file="$generated_dir/base/$role.yaml"
  target_file="$generated_dir/nodes/$name.yaml"

  export name interface address prefix gateway
  yq eval \
    'with(select(has("machine"));
      .machine.network.interfaces = [{
        "interface": strenv(interface),
        "addresses": [strenv(address) + "/" + strenv(prefix)],
        "routes": [{"network": "0.0.0.0/0", "gateway": strenv(gateway)}],
        "dhcp": false
      }]
    ) |
    with(select(.kind == "HostnameConfig");
      del(.auto) |
      .hostname = strenv(name)
    )' \
    "$source_file" > "$target_file"

  if [[ "$role" == "worker" ]]; then
    cat "$talos_dir/patches/longhorn-volume.yaml" >> "$target_file"
  fi
done

cp "$generated_dir/base/talosconfig" "$generated_dir/talosconfig"
controlplane_address="$(yq -r '.nodes[] | select(.role == "controlplane") | .address' "$config_file" | head -n1)"
talosctl --talosconfig "$generated_dir/talosconfig" config endpoint "$controlplane_address"
talosctl --talosconfig "$generated_dir/talosconfig" config node "$controlplane_address"

echo "Generated Talos configs in $generated_dir"
