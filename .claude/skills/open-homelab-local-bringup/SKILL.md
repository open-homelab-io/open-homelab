---
name: open-homelab-local-bringup
description: Bring an open-homelab cluster online using the default local/no-AWS path. Use when the user wants to deploy, bootstrap, validate, or troubleshoot open-homelab without AWS, Route53, ExternalDNS, or public ACME certificates.
---

# Open Homelab Local Bring-Up

Use this skill to guide a user from a fresh checkout to a working local/no-AWS `open-homelab` cluster.

## Read First

- `docs/getting-started.md`
- `docs/deployment-modes.md`
- `docs/configuration.md`
- `infra/proxmox/README.md`
- `clusters/production/talos/README.md`

Default mode uses local OpenTofu state, Proxmox-managed Talos VMs, MetalLB, Traefik, local DNS or `/etc/hosts`, and no Route53, ExternalDNS, or IAM Roles Anywhere.

## Preflight

Before running commands, verify the user customized:

- `.env`
- `infra/proxmox/config/production.yaml`
- `clusters/production/talos/config.yaml`
- platform hostnames under `platform/*/values.yaml`

Required tools: `bun`, `tofu` (OpenTofu), `kubectl`, `helm`, `talosctl`, `jq`, and `yq`.

Never print real values from `.env`, kubeconfigs, Talos secrets, OpenBao init files, private keys, or OpenTofu state.

## Bring Up

```bash
cd infra/proxmox
bun install
bun run get
bun run typecheck
bun run synth
bun run deploy
cd ../..
```

Bootstrap Talos and Kubernetes:

```bash
./clusters/production/talos/scripts/generate-config.sh
./clusters/production/talos/scripts/apply-config.sh
./clusters/production/talos/scripts/bootstrap.sh
KUBECONFIG=clusters/production/talos/generated/kubeconfig ./scripts/bootstrap-cilium.sh
./clusters/production/talos/scripts/approve-kubelet-csrs.sh
```

Install Argo CD with the default `clusters/production/gitops/root` path:

```bash
./scripts/bootstrap-argocd.sh
```

Seed platform secrets:

```bash
./scripts/bootstrap-openbao.sh
./scripts/bootstrap-openbao-external-secrets.sh
./scripts/bootstrap-keycloak-secrets.sh
./scripts/bootstrap-observability-secrets.sh
```

## Verify

```bash
export KUBECONFIG=clusters/production/talos/generated/kubeconfig
kubectl get nodes
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
kubectl -n argocd get applications -o wide
```

Confirm AWS resources are absent. This should print nothing:

```bash
kubectl get clusterissuer,ns,deploy,svc,ingress -A 2>/dev/null |
  grep -Ei 'external-dns|route53|rolesanywhere|letsencrypt'
```

## Common Recovery

If nodes are `NotReady`, check Cilium first. If External Secrets are not syncing after OpenBao bootstrap, restart `external-secrets` and force-refresh ExternalSecrets as documented in `docs/getting-started.md`.

If Proxmox destroy is needed, preview with:

```bash
CONFIRM_DESTROY_HOMELAB="destroy homelab" PLAN_ONLY=1 ./scripts/destroy-proxmox.sh
```
