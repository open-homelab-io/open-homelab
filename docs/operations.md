# Operations

This guide collects routine commands for running and rebuilding an `open-homelab` cluster.

## Environment

Most commands assume:

```bash
export KUBECONFIG=clusters/production/talos/generated/kubeconfig
```

## Health Checks

```bash
kubectl get nodes
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
kubectl -n argocd get applications -o wide
```

No-AWS deployments should not contain AWS DNS automation resources:

```bash
kubectl get clusterissuer,ns,deploy,svc,ingress -A 2>/dev/null |
  grep -Ei 'external-dns|route53|rolesanywhere|letsencrypt'
```

The command should print nothing.

## Refresh Argo CD Apps

```bash
for app in homelab-root homelab-secrets harbor-infra keycloak mimir longhorn-auth grafana harbor openbao; do
  kubectl -n argocd annotate application "${app}" argocd.argoproj.io/refresh=hard --overwrite || true
done
```

## Refresh External Secrets

Use this after changing OpenBao secrets or after bootstrapping OpenBao auth for the first time:

```bash
kubectl -n external-secrets rollout restart deploy/external-secrets
kubectl -n external-secrets rollout status deploy/external-secrets --timeout=120s

ts="$(date +%s)"
kubectl get externalsecrets -A \
  -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' |
  while read -r ns name; do
    kubectl -n "${ns}" annotate externalsecret "${name}" force-sync="${ts}" --overwrite
  done
```

## Proxmox Diff And Apply

```bash
cd infra/proxmox
bun run typecheck
bun run synth
bun run diff
bun run deploy
```

Use `LAB_CONFIG` to point at a different environment file:

```bash
LAB_CONFIG=infra/proxmox/config/production.yaml bun run synth
```

## Destroy Proxmox VMs

Preview first:

```bash
CONFIRM_DESTROY_HOMELAB="destroy homelab" PLAN_ONLY=1 ./scripts/destroy-proxmox.sh
```

Destroy Terraform-managed VMs:

```bash
CONFIRM_DESTROY_HOMELAB="destroy homelab" ./scripts/destroy-proxmox.sh
```

If local Terraform state is missing but the VMs exist in Proxmox, use the direct cleanup script. It only targets VM IDs listed in `infra/proxmox/config/production.yaml`.

```bash
./scripts/destroy-proxmox-vms.sh
CONFIRM_DESTROY_HOMELAB="destroy homelab" APPLY_DESTROY=1 ./scripts/destroy-proxmox-vms.sh
```

## Talos Regeneration

Regenerate machine configs after changing Talos config, patches, Kubernetes version, Talos version, node IPs, or the image-factory installer image:

```bash
./clusters/production/talos/scripts/generate-config.sh
```

Apply configs:

```bash
./clusters/production/talos/scripts/apply-config.sh
```

Bootstrap the first control plane only once per fresh cluster:

```bash
./clusters/production/talos/scripts/bootstrap.sh
```

## Longhorn Prerequisites

Longhorn requires Talos extensions for iSCSI and Linux utilities plus a worker data disk mounted as the `longhorn` user volume. See [../clusters/production/talos/README.md](../clusters/production/talos/README.md).

Bootstrap or rebuild the prerequisites with:

```bash
./clusters/production/talos/scripts/upgrade-longhorn-prereqs.sh
```

## Backup Notes

Before destructive work, capture:

- OpenBao recovery material and root-token state according to your own secret-handling policy
- exported Kubernetes manifests for anything not managed by GitOps
- Longhorn backups or snapshots for persistent volumes
- Terraform state if using local state

The repo intentionally does not prescribe a global backup provider yet.
