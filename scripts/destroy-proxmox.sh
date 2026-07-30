#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_file="$root_dir/.env"
stack_dir="$root_dir/infra/proxmox/cdktf.out/stacks/production"
confirm="${CONFIRM_DESTROY_HOMELAB:-}"

if [[ "$confirm" != "destroy homelab" ]]; then
  cat >&2 <<'EOF'
Refusing to destroy Proxmox resources without explicit confirmation.

Run:
  CONFIRM_DESTROY_HOMELAB="destroy homelab" ./scripts/destroy-proxmox.sh

Preview only:
  CONFIRM_DESTROY_HOMELAB="destroy homelab" PLAN_ONLY=1 ./scripts/destroy-proxmox.sh
EOF
  exit 1
fi

if [[ ! -f "$env_file" ]]; then
  echo "Missing $env_file. Copy .env.example to .env and fill in Proxmox credentials first." >&2
  exit 1
fi

set -a
# shellcheck source=/dev/null
. "$env_file"
set +a

if ! command -v terraform >/dev/null 2>&1; then
  echo "terraform is required on PATH." >&2
  exit 1
fi

if [[ ! -d "$stack_dir" ]]; then
  (
    cd "$root_dir/infra/proxmox"
    bun run synth
  )
fi

cd "$stack_dir"
terraform init -reconfigure
terraform plan -destroy -out=tfplan.destroy
terraform show -no-color tfplan.destroy

if [[ "${PLAN_ONLY:-0}" == "1" ]]; then
  echo "PLAN_ONLY=1 set; no resources destroyed."
  exit 0
fi

terraform apply tfplan.destroy
