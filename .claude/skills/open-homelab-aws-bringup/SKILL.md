---
name: open-homelab-aws-bringup
description: Add AWS-backed OpenTofu state or Route53 DNS automation to open-homelab. Use when the user wants S3 state, AWS, Route53, IAM Roles Anywhere, ExternalDNS, DNS-01 certificates, public ACME certificates, or AWS-enabled GitOps.
---

# Open Homelab AWS Bring-Up

Use this skill only for AWS add-ons. The base cluster still comes online through the local/no-AWS path unless the user explicitly wants AWS features.

## Read First

- `docs/deployment-modes.md`
- `docs/configuration.md`
- `infra/aws/README.md`
- `bootstrap/secrets/README.md`
- `clusters/production/gitops/README.md`

AWS has two independent paths: S3 OpenTofu state and Route53 DNS automation.

Do not enable AWS DNS automation implicitly; it creates real AWS IAM and Route53 resources.

## AWS OpenTofu State

Required `.env` values:

```bash
AWS_OPENTOFU_STATE_ENABLED=1
AWS_REGION=us-east-1
TF_STATE_BUCKET=open-homelab-opentofu-state-123456789012-us-east-1
TF_STATE_KEY=open-homelab/proxmox/production.tfstate
```

Deploy:

```bash
cd infra/aws
bun install
AWS_OPENTOFU_STATE_ENABLED=1 bun run typecheck
AWS_OPENTOFU_STATE_ENABLED=1 bun run synth
AWS_OPENTOFU_STATE_ENABLED=1 bun run deploy open-homelab-opentofu-state
```

Migrate existing Proxmox state only after the bucket exists:

```bash
cd ../proxmox
bun run synth
cd cdktf.out/stacks/production
set -a; . ../../../../../.env; set +a
tofu init -migrate-state
tofu plan
```

## AWS DNS Automation

Required `.env` values:

```bash
AWS_DNS_AUTOMATION_ENABLED=1
AWS_REGION=us-east-1
PUBLIC_DOMAIN=example.com
PUBLIC_HOSTED_ZONE_ID=Z00000000000000000000
CLUSTER_DOMAIN=lab.example.com
LETSENCRYPT_EMAIL=admin@example.com
```

Use `.env.example` for the full `IAM_ROLES_ANYWHERE_*` defaults. Before deploying, require the user to replace placeholders in `platform/dns/cluster-issuers.yaml`, `platform/external-dns/values.yaml`, and platform hostname values under `platform/*/values.yaml`.

Deploy:

```bash
scripts/bootstrap-rolesanywhere-ca.sh
cd infra/aws
AWS_DNS_AUTOMATION_ENABLED=1 bun run typecheck
AWS_DNS_AUTOMATION_ENABLED=1 bun run synth
AWS_DNS_AUTOMATION_ENABLED=1 bun run deploy open-homelab-dns-automation
cd ../..
scripts/bootstrap-rolesanywhere-dns.sh
```

Switch Argo CD to the AWS-enabled GitOps path:

```bash
ALLOW_AWS_GITOPS=1 GITOPS_ROOT_PATH=clusters/production/gitops ./scripts/bootstrap-argocd.sh
```

## Verify

```bash
kubectl -n cert-manager get pods
kubectl get clusterissuer
kubectl -n external-dns get pods
kubectl -n argocd get applications -o wide
```

Check Route53 changes in AWS before assuming DNS propagation is complete.

## Safety Rules
Never print AWS credentials, private keys, `.context/iam-roles-anywhere` key material, kubeconfigs, OpenBao root tokens, or OpenTofu state. If `PUBLIC_DOMAIN` or `PUBLIC_HOSTED_ZONE_ID` is still an example value, stop and ask the user to configure real AWS DNS values before deployment.
