# Getting Started

This guide deploys the default local/no-AWS path: Proxmox VMs, Talos Kubernetes, Cilium, Argo CD, and the platform app set.

## 1. Install Local Tools

Install these tools on your workstation:

- `bun`
- `terraform`
- `kubectl`
- `helm`
- `talosctl`
- `jq`
- `yq`
- optional: `gh`, when bootstrapping Argo CD against a private fork

See [runbooks/local-tooling.md](runbooks/local-tooling.md) for notes.

## 2. Configure Environment

```bash
cp .env.example .env
```

Edit `.env`:

```bash
LAB_CONFIG=infra/proxmox/config/production.yaml
TRAEFIK_LOAD_BALANCER_IP=192.168.5.46
PROXMOX_VE_ENDPOINT=https://pve.example.lan:8006/api2/json
PROXMOX_VE_API_TOKEN=user@pam!token-id=token-secret
KEYCLOAK_FIRST_ADMIN_USERNAME=admin
KEYCLOAK_FIRST_ADMIN_EMAIL=admin@example.com
KEYCLOAK_FIRST_ADMIN_TEMP_PASSWORD=
KEYCLOAK_FIRST_ADMIN_FIRST_NAME=Open
KEYCLOAK_FIRST_ADMIN_LAST_NAME=Homelab
```

Leave all AWS variables commented for the first deployment unless you intentionally want the optional AWS path.

## 3. Configure Proxmox

Edit [../infra/proxmox/config/production.yaml](../infra/proxmox/config/production.yaml):

- `cluster.gateway`, `cluster.cidrSuffix`, and node IP addresses
- `proxmox.defaultNodeName`, `isoNodeName`, and per-node `nodeName`
- `datastoreId`, `isoDatastoreId`, and `longhornDataDisk.datastoreByNodeName`
- `networkBridge` and optional `vlanId`
- VM IDs and node sizes

The sample inventory uses one control plane and five workers. You can reduce or expand the node list, but keep at least one `controlplane` node and enough worker capacity for Longhorn and the platform services.

## 4. Configure Talos

Edit [../clusters/production/talos/config.yaml](../clusters/production/talos/config.yaml):

- `cluster.endpoint`, usually `https://<control-plane-ip>:6443`
- `network.gateway`, `network.prefix`, and `network.interface`
- node `address` values matching the Proxmox VM addresses
- `maintenanceAddress` values used while Talos is still in maintenance mode
- `installDisk`, Kubernetes version, Talos version, and installer image

The Proxmox VM network interface is commonly `ens18`, but verify it in your Talos environment before applying static config.

## 5. Deploy Proxmox VMs

```bash
cd infra/proxmox
bun install
bun run get
bun run typecheck
bun run synth
bun run deploy
cd ../..
```

The CDKTN CLI currently shells out to `terraform` during provider generation, even if you prefer OpenTofu for later Terraform operations.

## 6. Bootstrap Kubernetes

The VMs must exist and be booted into Talos maintenance mode before applying machine config.

```bash
./clusters/production/talos/scripts/generate-config.sh
./clusters/production/talos/scripts/apply-config.sh
./clusters/production/talos/scripts/bootstrap.sh
KUBECONFIG=clusters/production/talos/generated/kubeconfig ./scripts/bootstrap-cilium.sh
./clusters/production/talos/scripts/approve-kubelet-csrs.sh
```

Check the cluster:

```bash
KUBECONFIG=clusters/production/talos/generated/kubeconfig kubectl get nodes
```

Nodes may stay `NotReady` until Cilium is installed. That is expected.

## 7. Bootstrap Argo CD

For the public upstream repo:

```bash
./scripts/bootstrap-argocd.sh
```

For a private fork:

```bash
export GITHUB_TOKEN=<token-with-repo-read-access>
export REPO_URL=https://github.com/your-org/your-open-homelab-fork.git
./scripts/bootstrap-argocd.sh
```

The default root path is `clusters/production/gitops/root`, which excludes Route53 issuers, ExternalDNS, and AWS-specific cert-manager values.

## 8. Bootstrap Secrets

After Argo CD starts applying the platform, initialize OpenBao and seed the secrets consumed by External Secrets Operator:

```bash
./scripts/bootstrap-openbao.sh
./scripts/bootstrap-openbao-external-secrets.sh
./scripts/bootstrap-keycloak-secrets.sh
./scripts/bootstrap-observability-secrets.sh
```

If External Secrets tried to connect before OpenBao Kubernetes auth was configured, restart and refresh:

```bash
export KUBECONFIG=clusters/production/talos/generated/kubeconfig

kubectl -n external-secrets rollout restart deploy/external-secrets
kubectl -n external-secrets rollout status deploy/external-secrets --timeout=120s

ts="$(date +%s)"
kubectl get externalsecrets -A \
  -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' |
  while read -r ns name; do
    kubectl -n "${ns}" annotate externalsecret "${name}" force-sync="${ts}" --overwrite
  done
```

## 9. Verify

```bash
kubectl get nodes
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
kubectl -n argocd get applications -o wide
```

Expected state:

- every Kubernetes node is `Ready`
- no pods are stuck outside `Running` or `Succeeded`
- every Argo CD app is `Synced` and `Healthy`
- the no-AWS path has no `external-dns`, `route53`, `rolesanywhere`, or `letsencrypt` resources

Check the last condition:

```bash
kubectl get clusterissuer,ns,deploy,svc,ingress -A 2>/dev/null |
  grep -Ei 'external-dns|route53|rolesanywhere|letsencrypt'
```

The command should print nothing on the no-AWS path.

## 10. Local Access

Without AWS DNS automation, point local DNS or `/etc/hosts` records at Traefik's LoadBalancer IP:

```bash
sudo tee -a /etc/hosts >/dev/null <<'EOF'
192.168.5.46 argo.lab.example.com
192.168.5.46 auth.lab.example.com
192.168.5.46 grafana.lab.example.com
192.168.5.46 harbor.lab.example.com
192.168.5.46 longhorn.lab.example.com
192.168.5.46 bao.lab.example.com
EOF
```

Open:

- `https://argo.lab.example.com`
- `https://auth.lab.example.com`
- `https://grafana.lab.example.com`
- `https://harbor.lab.example.com`
- `https://longhorn.lab.example.com`
- `https://bao.lab.example.com`

Browser TLS warnings are expected on the no-AWS path because public DNS-01 ACME certificates are disabled.

## Optional AWS Path

AWS resources are opt-in. Leave the AWS variables commented in `.env` to avoid Route53, IAM Roles Anywhere, and S3-backed Terraform state.

To use S3 for Terraform state:

```bash
cd infra/aws
bun install
AWS_TERRAFORM_STATE_ENABLED=1 bun run synth
AWS_TERRAFORM_STATE_ENABLED=1 bun run deploy open-homelab-terraform-state
```

Then set `AWS_REGION`, `TF_STATE_BUCKET`, and `TF_STATE_KEY` in `.env` before migrating Proxmox state.

To use Route53 for cert-manager DNS-01 and ExternalDNS:

```bash
scripts/bootstrap-rolesanywhere-ca.sh
cd infra/aws
AWS_DNS_AUTOMATION_ENABLED=1 bun run deploy open-homelab-dns-automation
cd ../..
scripts/bootstrap-rolesanywhere-dns.sh
ALLOW_AWS_GITOPS=1 GITOPS_ROOT_PATH=clusters/production/gitops scripts/bootstrap-argocd.sh
```

Before enabling this path, set `PUBLIC_DOMAIN`, `PUBLIC_HOSTED_ZONE_ID`, `CLUSTER_DOMAIN`, and `LETSENCRYPT_EMAIL` in `.env`, then update the DNS-related values under `platform/dns` and `platform/external-dns`.
