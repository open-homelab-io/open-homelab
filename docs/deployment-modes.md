# Deployment Modes

`open-homelab` supports a default local/no-AWS deployment and two optional AWS additions. Start local unless you already know you want AWS-backed state, Route53 DNS automation, or public ACME certificates.

## Local / No-AWS

Use this mode when you want everything to run on your LAN without cloud dependencies.

What it uses:

- local OpenTofu state
- Proxmox for Talos VMs
- MetalLB for LoadBalancer IPs
- local DNS or `/etc/hosts`
- cert-manager without Route53 DNS-01 issuers
- no ExternalDNS
- no IAM Roles Anywhere

Required configuration:

- `.env`
- `infra/proxmox/config/production.yaml`
- `clusters/production/talos/config.yaml`
- platform hostnames under `platform/*/values.yaml`

Deploy:

```bash
cd infra/proxmox
bun install
bun run get
bun run typecheck
bun run synth
bun run deploy
cd ../..

./clusters/production/talos/scripts/generate-config.sh
./clusters/production/talos/scripts/apply-config.sh
./clusters/production/talos/scripts/bootstrap.sh
KUBECONFIG=clusters/production/talos/generated/kubeconfig ./scripts/bootstrap-cilium.sh
./clusters/production/talos/scripts/approve-kubelet-csrs.sh
./scripts/bootstrap-argocd.sh
```

Argo CD defaults to:

```text
clusters/production/gitops/root
```

That path intentionally excludes AWS DNS automation.

Expected access model:

```text
local DNS or /etc/hosts -> Traefik LoadBalancer IP -> platform ingresses
```

TLS browser warnings are expected unless you provide your own trusted local CA or enable the AWS DNS path for public ACME certificates.

## AWS OpenTofu State

Use this mode when you want Proxmox OpenTofu/CDKTN state in S3 instead of a local state file.

What it adds:

- S3 bucket for OpenTofu state
- bucket versioning
- S3-managed encryption
- native S3 lockfile locking

Required `.env` values:

```bash
AWS_OPENTOFU_STATE_ENABLED=1
AWS_REGION=us-east-1
TF_STATE_BUCKET=open-homelab-opentofu-state-123456789012-us-east-1
TF_STATE_KEY=open-homelab/proxmox/production.tfstate
```

Deploy the state bucket:

```bash
cd infra/aws
bun install
AWS_OPENTOFU_STATE_ENABLED=1 bun run typecheck
AWS_OPENTOFU_STATE_ENABLED=1 bun run synth
AWS_OPENTOFU_STATE_ENABLED=1 bun run deploy open-homelab-opentofu-state
```

Then migrate Proxmox state:

```bash
cd ../proxmox
bun run synth
cd cdktf.out/stacks/production
set -a; . ../../../../../.env; set +a
tofu init -migrate-state
tofu plan
```

## AWS DNS Automation

Use this mode when you want Route53 DNS records, cert-manager DNS-01 validation, ExternalDNS, and public ACME certificates.

What it adds:

- IAM Roles Anywhere trust anchor and profile
- Route53 automation IAM role
- cert-manager Route53 DNS-01 issuers
- ExternalDNS
- AWS-enabled Argo CD GitOps path

Required `.env` values:

```bash
AWS_DNS_AUTOMATION_ENABLED=1
AWS_REGION=us-east-1
PUBLIC_DOMAIN=example.com
PUBLIC_HOSTED_ZONE_ID=Z00000000000000000000
CLUSTER_DOMAIN=lab.example.com
LETSENCRYPT_EMAIL=admin@example.com
IAM_ROLES_ANYWHERE_STACK_NAME=open-homelab-dns-automation
IAM_ROLES_ANYWHERE_PKI_DIR=.context/iam-roles-anywhere
IAM_ROLES_ANYWHERE_CA_CERT_PATH=../../.context/iam-roles-anywhere/ca.crt
IAM_ROLES_ANYWHERE_CLIENT_CERT_PATH=.context/iam-roles-anywhere/dns.crt
IAM_ROLES_ANYWHERE_CLIENT_KEY_PATH=.context/iam-roles-anywhere/dns.key
IAM_ROLES_ANYWHERE_CA_CN=open-homelab-rolesanywhere-ca
IAM_ROLES_ANYWHERE_CLIENT_CN=open-homelab-dns-automation
```

Before deploying, update:

- `platform/dns/cluster-issuers.yaml`
- `platform/external-dns/values.yaml`
- any platform hostname values using your cluster domain

Deploy DNS automation:

```bash
scripts/bootstrap-rolesanywhere-ca.sh
cd infra/aws
AWS_DNS_AUTOMATION_ENABLED=1 bun run typecheck
AWS_DNS_AUTOMATION_ENABLED=1 bun run synth
AWS_DNS_AUTOMATION_ENABLED=1 bun run deploy open-homelab-dns-automation
cd ../..
scripts/bootstrap-rolesanywhere-dns.sh
```

Bootstrap or update Argo CD with the AWS-enabled path:

```bash
ALLOW_AWS_GITOPS=1 GITOPS_ROOT_PATH=clusters/production/gitops ./scripts/bootstrap-argocd.sh
```

## Choosing A Mode

Use local/no-AWS when:

- you want the fastest first deployment
- you do not own a public Route53 hosted zone
- local DNS and browser TLS warnings are acceptable

Add AWS OpenTofu state when:

- multiple operators need shared OpenTofu state
- you want versioned remote state
- you are comfortable managing an AWS account for state only

Add AWS DNS automation when:

- you own a public Route53 hosted zone
- you want public ACME certificates
- you want DNS records managed from Kubernetes
