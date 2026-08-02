# Production Talos Cluster

This directory holds the declarative machine-configuration inputs for the production Kubernetes cluster.

Seeded node plan:

| Node | Role | Address |
| --- | --- | --- |
| controller-1 | controlplane | 192.168.5.55 |
| worker-01 | worker | 192.168.5.101 |
| worker-02 | worker | 192.168.5.102 |
| worker-07 | worker | 192.168.5.107 |
| worker-08 | worker | 192.168.5.108 |
| worker-09 | worker | 192.168.5.109 |

Recommended bootstrap flow:

```bash
./clusters/production/talos/scripts/generate-config.sh
./clusters/production/talos/scripts/apply-config.sh
./clusters/production/talos/scripts/bootstrap.sh
KUBECONFIG=clusters/production/talos/generated/kubeconfig ./scripts/bootstrap-cilium.sh
./clusters/production/talos/scripts/approve-kubelet-csrs.sh
KUBECONFIG=clusters/production/talos/generated/kubeconfig kubectl get nodes
```

## CNI: Cilium

Talos is configured with `cni.name: none` and `proxy.disabled: true` in
`patches/controlplane.yaml`, so it ships **no** CNI or kube-proxy. Cilium
replaces Flannel and runs in kube-proxy replacement mode.

Because Argo CD cannot schedule pods before a CNI exists, Cilium is installed
out-of-band by `scripts/bootstrap-cilium.sh` immediately after
`bootstrap.sh` and before Argo CD. Until Cilium is installed the nodes stay
`NotReady` — this is expected. Argo CD then adopts the same Helm release
(`clusters/production/gitops/root/cilium.yaml`) for ongoing lifecycle
management, with values in `platform/cilium/values.yaml`.

Commit patches and non-secret inputs. Do not commit `secrets.yaml`, generated kubeconfigs, or generated talosconfigs.

The VMs must exist and be booted into Talos maintenance mode before the first `apply-config.sh` will work. On a fresh install the script uses `maintenanceAddress` values from `config.yaml` when the final static IP is not live yet. Once configs are applied, it uses each node's static address.

The Proxmox virtio NIC name observed by Talos is `ens18`; the static network config depends on that interface name.

## Longhorn Prerequisites

Longhorn needs Talos nodes booted with `siderolabs/iscsi-tools` and `siderolabs/util-linux-tools`.
The image-factory schematic is committed in `schematic.yaml`, and the matching installer image is set in `config.yaml`.

Proxmox worker VMs also need their dedicated Longhorn data disks before Talos can create the `longhorn` user volume:

```bash
cd infra/proxmox
bun run synth
cd cdktf.out/stacks/production
set -a; . ../../../../../.env; set +a
tofu plan
tofu apply
cd ../../../../..
```

The OpenTofu config attaches a second worker-only disk at `scsi1`. Talos provisions that disk as a `UserVolumeConfig` named `longhorn`, mounted at `/var/mnt/longhorn`.

After the Proxmox disks are attached, apply the staged kubelet mount config and roll the nodes through the extension-bearing Talos installer:

```bash
./clusters/production/talos/scripts/upgrade-longhorn-prereqs.sh
```

The script is a bootstrap/rebuild operation, not a steady-state deployment path. It processes workers before the control plane and accepts `ONLY_NODES="worker-02 worker-07"` when resuming a partial rollout.

After the script completes, verify:

```bash
talosctl --talosconfig clusters/production/talos/generated/talosconfig -n 192.168.5.101 get extensions
talosctl --talosconfig clusters/production/talos/generated/talosconfig -n 192.168.5.101 read /usr/local/sbin/iscsiadm >/dev/null
talosctl --talosconfig clusters/production/talos/generated/talosconfig -n 192.168.5.101 get volumestatus u-longhorn
```

The Longhorn Argo application is managed by the root GitOps app at `clusters/production/gitops/root/longhorn.yaml`.

Current generated assets:

- `secrets.yaml`: local Talos secrets; ignored by Git.
- `generated/nodes/*.yaml`: per-node machine configs; ignored by Git.
- `generated/talosconfig`: local Talos client config; ignored by Git.

Non-destructive readiness check:

```bash
for ip in 192.168.5.55 192.168.5.101 192.168.5.102 192.168.5.107 192.168.5.108 192.168.5.109; do
  nc -G 2 -z "$ip" 50000 && echo "$ip talos-api-open" || echo "$ip talos-api-closed"
done
```
