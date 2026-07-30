#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_file="$root_dir/.env"
config_file="${LAB_CONFIG:-infra/proxmox/config/production.yaml}"
apply_destroy="${APPLY_DESTROY:-0}"
confirm="${CONFIRM_DESTROY_HOMELAB:-}"

if [[ ! -f "$env_file" ]]; then
  echo "Missing $env_file. Copy .env.example to .env and fill in Proxmox credentials first." >&2
  exit 1
fi

set -a
# shellcheck source=/dev/null
. "$env_file"
set +a

config_path="$root_dir/$config_file"
if [[ ! -f "$config_path" ]]; then
  echo "Missing lab config at $config_path" >&2
  exit 1
fi

for command in curl jq yq; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "$command is required on PATH." >&2
    exit 1
  fi
done

if [[ -z "${PROXMOX_VE_ENDPOINT:-}" || -z "${PROXMOX_VE_API_TOKEN:-}" ]]; then
  echo "PROXMOX_VE_ENDPOINT and PROXMOX_VE_API_TOKEN must be set in $env_file." >&2
  exit 1
fi

if [[ "$apply_destroy" == "1" && "$confirm" != "destroy homelab" ]]; then
  cat >&2 <<'EOF'
Refusing to delete Proxmox VMs without explicit confirmation.

Preview only:
  ./scripts/destroy-proxmox-vms.sh

Destroy the VMs listed in infra/proxmox/config/production.yaml:
  CONFIRM_DESTROY_HOMELAB="destroy homelab" APPLY_DESTROY=1 ./scripts/destroy-proxmox-vms.sh
EOF
  exit 1
fi

api() {
  local method="$1"
  local path="$2"
  shift 2
  curl -ksS --fail-with-body \
    -X "$method" \
    -H "Authorization: PVEAPIToken=${PROXMOX_VE_API_TOKEN}" \
    "${PROXMOX_VE_ENDPOINT%/}${path}" \
    "$@"
}

configured_vms="$(
  yq -o=json '.nodes[] | {"vmid": .vmId, "expectedName": .name}' "$config_path" |
    jq -s '.'
)"
proxmox_vms="$(api GET "/cluster/resources?type=vm" | jq '.data')"

matches="$(
  jq -n \
    --argjson wanted "$configured_vms" \
    --argjson actual "$proxmox_vms" \
    '
      $wanted
      | map(
          . as $w
          | ($actual[]? | select(.vmid == $w.vmid)) as $a
          | {
              vmid: $w.vmid,
              expectedName: $w.expectedName,
              name: ($a.name // null),
              node: ($a.node // null),
              status: ($a.status // "absent")
            }
        )
    '
)"

echo "$matches" | jq -r '
  .[]
  | [
      .vmid,
      .expectedName,
      (.name // "-"),
      (.node // "-"),
      .status
    ]
  | @tsv
' | awk 'BEGIN { print "vmid\texpected\tactual\tnode\tstatus" } { print }'

if [[ "$apply_destroy" != "1" ]]; then
  echo
  echo "Preview only; no VMs deleted."
  exit 0
fi

echo "$matches" | jq -c '.[] | select(.status != "absent")' | while read -r vm; do
  vmid="$(jq -r '.vmid' <<<"$vm")"
  name="$(jq -r '.name' <<<"$vm")"
  node="$(jq -r '.node' <<<"$vm")"
  status="$(jq -r '.status' <<<"$vm")"

  if [[ "$status" == "running" ]]; then
    echo "Stopping $name ($vmid) on $node"
    api POST "/nodes/${node}/qemu/${vmid}/status/stop" >/dev/null

    for _ in $(seq 1 60); do
      status="$(api GET "/nodes/${node}/qemu/${vmid}/status/current" | jq -r '.data.status')"
      [[ "$status" == "stopped" ]] && break
      sleep 2
    done

    if [[ "$status" != "stopped" ]]; then
      echo "$name ($vmid) did not stop cleanly; skipping destroy." >&2
      continue
    fi
  fi

  echo "Deleting $name ($vmid) on $node"
  api DELETE "/nodes/${node}/qemu/${vmid}?purge=1&destroy-unreferenced-disks=1" >/dev/null
done

echo "Requested deletion for configured Proxmox VMs."
