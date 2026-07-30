# open-homelab

`open-homelab` is a code-first, open source home lab stack for running a production-shaped Kubernetes platform on Proxmox.

The repo owns the whole path from virtual machines to platform services:

1. Proxmox VM provisioning with CDKTN and the `bpg/proxmox` Terraform provider.
2. Talos Linux machine configuration for Kubernetes nodes.
3. Argo CD GitOps bootstrap.
4. Cluster platform services for ingress, storage, identity, secrets, observability, certificates, and DNS.
5. User workloads such as game servers, Home Assistant, databases, and self-hosted runners.

The default path is local-first and does not require AWS. Optional AWS support adds S3-backed Terraform state plus Route53 DNS automation and public ACME certificates.

## What You Get

- Kubernetes on Talos Linux
- Cilium CNI with kube-proxy replacement
- MetalLB and Traefik ingress
- Longhorn distributed storage
- cert-manager
- Argo CD app-of-apps GitOps
- OpenBao and External Secrets Operator
- Keycloak SSO for platform tools
- Harbor registry
- Grafana, Loki, Tempo, Mimir, and Alloy/k8s-monitoring
- Optional Route53 and IAM Roles Anywhere DNS automation

## Repository Layout

```text
infra/aws/                 Optional AWS CDK stacks
infra/proxmox/             Proxmox VM provisioning app
clusters/production/talos/ Talos cluster configuration and bootstrap scripts
clusters/production/gitops/ Argo CD bootstrap and app-of-apps manifests
platform/                  Cluster platform apps and shared infrastructure
workloads/                 User-facing workloads
bootstrap/secrets/         Secret bootstrap notes
docs/                      Guides, architecture notes, and runbooks
scripts/                   Bootstrap, destroy, and operational scripts
```

## Quick Start

Prerequisites:

- Proxmox VE cluster or host
- A routable LAN IP range for Kubernetes nodes and MetalLB
- `bun`, `terraform`, `kubectl`, `helm`, `talosctl`, `jq`, and `yq`

Start here:

```bash
git clone https://github.com/open-homelab-io/open-homelab.git
cd open-homelab
cp .env.example .env
```

Then customize:

- `.env`
- `infra/proxmox/config/production.yaml`
- `clusters/production/talos/config.yaml`
- platform hostnames in `platform/*/values.yaml`

Deploy the local no-AWS path:

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

Continue with the full guide: [docs/getting-started.md](docs/getting-started.md).

## Deployment Modes

- `local/no-AWS`: local Terraform state, local DNS or `/etc/hosts`, no Route53, no ExternalDNS, and no public ACME certificates.
- `AWS state`: optional S3 state backend for Terraform/CDKTN.
- `AWS DNS`: optional Route53 DNS-01 certificates and ExternalDNS through IAM Roles Anywhere.

The no-AWS path is the default. AWS features are opt-in through environment flags.

## Documentation

- [Getting started](docs/getting-started.md)
- [Deployment modes](docs/deployment-modes.md)
- [Configuration guide](docs/configuration.md)
- [Architecture layers](docs/architecture/layers.md)
- [Operations guide](docs/operations.md)
- [Local tooling runbook](docs/runbooks/local-tooling.md)
- [OpenBao runbook](docs/runbooks/openbao.md)
- [Keycloak runbook](docs/runbooks/keycloak.md)
- [SSO runbook](docs/runbooks/sso.md)
- [Migration notes](docs/runbooks/migration-from-existing-homelab.md)

## Agent Support

Claude Code can use the repo-local skills in [.claude/skills](.claude/skills):

- `open-homelab-local-bringup`: local/no-AWS deployment and recovery
- `open-homelab-aws-bringup`: optional AWS state and DNS automation

## Public Template Notes

The checked-in `production` cluster is a working example topology. Before deploying, change the Proxmox node names, datastore names, network bridge, VLAN, IP addresses, domains, hosted zone IDs, and admin identity values to match your environment.

Generated Talos secrets, kubeconfigs, Terraform state, and `.env` are ignored by Git and must stay out of commits.

## Contributing

Issues, docs fixes, and focused pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a change.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
