# AWS Infrastructure

This AWS CDK app owns homelab AWS resources.

All stacks are opt-in. With no enable flags set, the app synthesizes no AWS resources.

Available stacks:

- `open-homelab-opentofu-state`: S3 bucket used for OpenTofu/CDKTN remote state. Enable with `AWS_OPENTOFU_STATE_ENABLED=1`.
- `open-homelab-dns-automation`: IAM Roles Anywhere trust anchor, profile, and Route53 role for Kubernetes DNS automation. Enable with `AWS_DNS_AUTOMATION_ENABLED=1`.

## Setup

```bash
cd infra/aws
bun install
bun run typecheck
AWS_OPENTOFU_STATE_ENABLED=1 AWS_DNS_AUTOMATION_ENABLED=1 bun run synth
```

The scripts load the repo-root `.env`, so these values can live there:

```bash
AWS_OPENTOFU_STATE_ENABLED=1
AWS_DNS_AUTOMATION_ENABLED=1
AWS_REGION=us-east-1
TF_STATE_BUCKET=open-homelab-opentofu-state-123456789012-us-east-1
TF_STATE_KEY=open-homelab/proxmox/production.tfstate
PUBLIC_DOMAIN=example.com
PUBLIC_HOSTED_ZONE_ID=Z00000000000000000000
IAM_ROLES_ANYWHERE_CA_CERT_PATH=../../.context/iam-roles-anywhere/ca.crt
```

If `TF_STATE_BUCKET` is omitted, the CDK stack uses:

```text
open-homelab-opentofu-state-${AWS_ACCOUNT_ID}-${AWS_REGION}
```

## Deploy

Deploy only the stacks you want:

```bash
AWS_OPENTOFU_STATE_ENABLED=1 bun run deploy open-homelab-opentofu-state
```

The DNS automation stack needs a local CA certificate before synth/deploy:

```bash
cd ../..
scripts/bootstrap-rolesanywhere-ca.sh
cd infra/aws
AWS_DNS_AUTOMATION_ENABLED=1 bun run deploy open-homelab-dns-automation
cd ../..
scripts/bootstrap-rolesanywhere-dns.sh
```

`PUBLIC_DOMAIN` and `PUBLIC_HOSTED_ZONE_ID` are required when `AWS_DNS_AUTOMATION_ENABLED=1`.

The CA key remains in `.context/iam-roles-anywhere` and is not committed. The Kubernetes cluster receives only the signed workload certificate/key used by the Roles Anywhere credential-helper sidecars.

After deployment, set `TF_STATE_BUCKET`, `TF_STATE_KEY`, and `AWS_REGION` in the root `.env`, then migrate the Proxmox OpenTofu state:

```bash
cd ../proxmox
bun run synth
cd cdktf.out/stacks/production
set -a; . ../../../../../.env; set +a
tofu init -migrate-state
tofu plan
```

The Proxmox CDKTN stack uses S3 native lockfile locking via `use_lockfile = true`.
