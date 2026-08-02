# Proxmox CDKTN Layer

This CDKTN app provisions Proxmox VMs with the `bpg/proxmox` OpenTofu provider.

It uses generated CDKTN bindings from `.gen/providers/proxmox`. Run `bun run get` after install and whenever the provider version changes.

## Setup

```bash
cd ../..
cp .env.example .env
cd infra/proxmox
bun install
bun run get
bun run typecheck
bun run synth
```

Edit the root `.env` with the real Proxmox endpoint and token before planning or applying. The Bun scripts load `../../.env` so OpenTofu provider credentials stay in process environment instead of synthesized JSON.

Use `LAB_CONFIG=infra/proxmox/config/production.yaml` in the root `.env` to point at a different config file. Relative paths are resolved from the repo root.

`bun run get` requires a `tofu` executable on `PATH`; the Bun scripts set `TERRAFORM_BINARY_NAME=tofu`, so CDKTN shells out to OpenTofu while generating provider bindings.

If `TF_STATE_BUCKET` is set in the root `.env`, the stack synthesizes an S3 backend with native lockfile locking:

```bash
AWS_REGION=us-east-1
TF_STATE_BUCKET=open-homelab-opentofu-state-123456789012-us-east-1
TF_STATE_KEY=open-homelab/proxmox/production.tfstate
```

After enabling those values for an existing local state, run `tofu init -migrate-state` from `cdktf.out/stacks/production`.

If Proxmox node hostnames are not resolvable during apply, fill in the optional `proxmox.ssh.nodes` block in `config/production.yaml`. The `bpg/proxmox` provider supports explicit SSH node address mappings, which avoids relying on hostname lookup for each Proxmox node.

Sample production config notes:

- Talos ISO is downloaded as managed Proxmox storage content on `proxmox-host-nfs`.
- VM boot disks currently use `shared-nfs-storage-pool` because `local-lvm` is not active on every online Proxmox node.
- Kubernetes persistent storage is not backed by NFS; Longhorn uses dedicated worker data disks on node-local Proxmox storage.
- VM NICs use `vmbr0` with VLAN tag `5`, matching the sample subnet.
- The sample node placement uses `proxmox1` and `proxmox3`; change node names to match your Proxmox cluster.

## Apply

Install OpenTofu, then run:

```bash
bun run diff
bun run deploy
```

For non-interactive apply from the synthesized stack:

```bash
cd cdktf.out/stacks/production
set -a; . ../../../../../.env; set +a
tofu apply -auto-approve
```

The API token must be allowed to allocate and configure VMs on the target nodes and storage. A 403 during VM creation means the token is valid but its effective ACLs are too narrow. Check both the user and the API token if token privilege separation is enabled.

## Destroy

The root destroy helper targets the synthesized `production` stack and refuses to run unless you provide the confirmation phrase. If `TF_STATE_BUCKET` is set in the root `.env`, it uses the S3 backend for OpenTofu state.

Preview first:

```bash
CONFIRM_DESTROY_HOMELAB="destroy homelab" PLAN_ONLY=1 ./scripts/destroy-proxmox.sh
```

Destroy:

```bash
CONFIRM_DESTROY_HOMELAB="destroy homelab" ./scripts/destroy-proxmox.sh
```

If OpenTofu reports that it has no objects to destroy but the configured VMs still exist in Proxmox, preview and then run the direct VM cleanup helper:

```bash
./scripts/destroy-proxmox-vms.sh
CONFIRM_DESTROY_HOMELAB="destroy homelab" APPLY_DESTROY=1 ./scripts/destroy-proxmox-vms.sh
```

You can check the token's effective privileges without printing the token:

```bash
set -a; . ../../.env; set +a
for path in / /nodes /vms /storage; do
  echo "$path"
  curl -ksS -H "Authorization: PVEAPIToken=$PROXMOX_VE_API_TOKEN" \
    "$PROXMOX_VE_ENDPOINT/access/permissions?path=$(printf %s "$path" | sed 's#/#%2F#g')" | jq -c '.data'
done
```

## Provider Notes

The OpenTofu provider constraint is pinned in `cdktf.json` to `bpg/proxmox@0.111.1`, which was the latest stable version visible from the OpenTofu Registry metadata during scaffold creation.

Review the synthesized JSON before the first apply. Proxmox provider schemas change over time, and the raw adapter intentionally exposes the provider attribute names directly.
