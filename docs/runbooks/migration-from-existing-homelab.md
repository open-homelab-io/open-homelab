# Migration From An Existing Homelab

## What Exists Today

Many existing homelab repositories start after Kubernetes already exists. A typical legacy setup contains:

- ArgoCD applications for platform and workloads.
- Vendored Helm charts for several platform components.
- Ansible playbooks for Kubernetes node updates.
- A Kubernetes inventory with one controller and five workers on `192.168.5.0/24`.
- Several secret manifests that should not be copied into the new repo as plaintext desired state.

Common application migration targets:

- `actions-runner-controller`
- `cert-manager`
- `factorio`
- `minecraft`
- `palworld`
- `satisfactory`
- `home-assistant`
- `influxdb`
- `nginx-ingress`
- `metallb-system`
- `prometheus`
- `vault` (legacy target; replace with OpenBao in this repo)
- `authentik` (legacy target; replace with Keycloak in this repo)

## Migration Order

1. Fill in real Proxmox settings in `infra/proxmox/config/production.yaml`.
2. Add or import the Talos image/template in Proxmox.
3. Run CDKTN synth and review the generated OpenTofu JSON.
4. Apply the Proxmox VM layer.
5. Generate Talos machine config for `controller-1` and workers.
6. Bootstrap Kubernetes.
7. Install ArgoCD with only the bootstrap entrypoint.
8. Move active applications from the old repo into `platform` or `workloads`.
9. Replace plaintext Kubernetes `Secret` manifests with ExternalSecret or SOPS-encrypted manifests.
10. Retire the old Ansible upgrade path once node lifecycle is fully covered by Talos upgrades.
11. Replace Authentik with Keycloak at `auth.lab.example.com`.

## Vendored Charts

Do not copy vendored chart trees by default. Prefer ArgoCD sources that reference upstream Helm repositories plus local values files. Vendor a chart only when you intentionally fork it.

## Secrets

Do not copy legacy secret manifests directly. Examples of manifests that should be converted instead of copied:

- `kubernetes/authentik/authentik-secret.yaml`
- `kubernetes/authentik/authentik-postgres-secret.yaml`
- `kubernetes/lets-encrypt/prod-route53-credentials-secret.yaml`
- `kubernetes/prometheus/secret.yaml`
- `kubernetes/vault/cluster-secret-store.yaml` (legacy Vault path; replace with OpenBao-backed External Secrets config)

Use `bootstrap/secrets/README.md` as the place to document secret prerequisites and recovery steps without storing secret values.
