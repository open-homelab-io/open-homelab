# Configuration

`open-homelab` is a template. Treat the checked-in `production` files as a working example, then replace the environment-specific values before deploying.

## Root Environment

Create `.env` from [.env.example](../.env.example). The root `.env` is loaded by the Proxmox and AWS scripts and is ignored by Git.

Required for local/no-AWS:

- `LAB_CONFIG`: Proxmox config file path.
- `TRAEFIK_LOAD_BALANCER_IP`: MetalLB IP assigned to Traefik.
- `PROXMOX_VE_ENDPOINT`: Proxmox API endpoint.
- `PROXMOX_VE_API_TOKEN`: Proxmox API token in provider format.
- `KEYCLOAK_FIRST_ADMIN_*`: first human platform administrator.

Optional for AWS state:

- `AWS_OPENTOFU_STATE_ENABLED=1`
- `AWS_REGION`
- `TF_STATE_BUCKET`
- `TF_STATE_KEY`

Optional for AWS DNS automation:

- `AWS_DNS_AUTOMATION_ENABLED=1`
- `PUBLIC_DOMAIN`
- `PUBLIC_HOSTED_ZONE_ID`
- `CLUSTER_DOMAIN`
- `LETSENCRYPT_EMAIL`
- `IAM_ROLES_ANYWHERE_*`

## Proxmox

Primary file: [../infra/proxmox/config/production.yaml](../infra/proxmox/config/production.yaml)

Update:

- cluster gateway, DNS domain, and CIDR suffix
- Proxmox node names
- datastore IDs
- ISO datastore and Talos image settings
- bridge and VLAN
- Longhorn data disk datastore map
- VM IDs, node names, addresses, CPU, memory, and disk sizes

The sample leaves `macAddress` unset so Proxmox can allocate VM NIC addresses. Add static MAC addresses only if your network requires DHCP reservations or deterministic interface mapping.

## Talos

Primary file: [../clusters/production/talos/config.yaml](../clusters/production/talos/config.yaml)

Keep this file aligned with the Proxmox VM inventory:

- `cluster.endpoint` should point at a control-plane node.
- `nodes[].address` should match Proxmox VM static IPs.
- `nodes[].maintenanceAddress` should match the temporary addresses Talos has before machine config is applied.
- `network.interface` must match the NIC name seen by Talos.
- `talosInstallerImage` should match the committed image-factory schematic when Longhorn prerequisites are enabled.

Generated files under `clusters/production/talos/generated/` and `clusters/production/talos/secrets.yaml` are local secrets and are ignored.

## Domains And URLs

The example hostnames use `lab.example.com`:

- `argo.lab.example.com`
- `auth.lab.example.com`
- `grafana.lab.example.com`
- `harbor.lab.example.com`
- `longhorn.lab.example.com`
- `bao.lab.example.com`

Update these files when changing the cluster domain:

- `platform/argocd/values.yaml`
- `platform/grafana/values.yaml`
- `platform/harbor/values.yaml`
- `platform/harbor/resources/external-secret.yaml`
- `platform/keycloak/keycloak.yaml`
- `platform/keycloak/bootstrap-admin-user-job.yaml`
- `platform/longhorn-auth/values.yaml`
- `platform/openbao/values.yaml`
- `scripts/bootstrap-openbao-keycloak-oidc.sh`

For the AWS DNS path, also update:

- `platform/dns/cluster-issuers.yaml`
- `platform/external-dns/values.yaml`

## GitOps Repository

The upstream public repo URL is:

```text
https://github.com/open-homelab-io/open-homelab.git
```

For a fork, replace that URL in Argo CD Application manifests under [../clusters/production/gitops](../clusters/production/gitops), then bootstrap with:

```bash
REPO_URL=https://github.com/your-org/your-fork.git ./scripts/bootstrap-argocd.sh
```

Use `GITHUB_TOKEN` or an authenticated `gh` CLI session when the repo is private.

## Secrets

Do not commit:

- `.env`
- OpenTofu state
- Talos `secrets.yaml`
- generated kubeconfigs and talosconfigs
- OpenBao unseal keys or root tokens
- IAM Roles Anywhere private keys and certificates

Secrets consumed by Kubernetes apps are seeded into OpenBao, then synced into namespaces by External Secrets Operator.
