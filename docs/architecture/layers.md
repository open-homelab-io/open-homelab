# Architecture Layers

The repo is split by responsibility, not by tool.

## Layer 1: Proxmox Infrastructure

`infra/proxmox` owns Proxmox objects:

- VM declarations
- CPU, memory, disk, and network shape
- static addresses used by the cluster nodes
- provider connection settings

This layer should not install Kubernetes packages or mutate cluster workloads. Its output is compute capacity with predictable addresses.

## Layer 2: Machine Configuration

`clusters/production/talos` owns host operating-system configuration.

Talos is the recommended target because its machine config is declarative and versionable. If you choose Debian/Ubuntu instead, keep that layer declarative with cloud-init plus Ansible pull-mode, and do not put one-off SSH procedures in the normal path.

## Layer 3: Cluster Bootstrap

`clusters/production/gitops` owns the minimal manifests needed to let ArgoCD take over.

Keep this layer small:

- ArgoCD install values
- app-of-apps or ApplicationSet entrypoint
- repository credentials
- secret-store bootstrap references

## Layer 4: Platform

`platform` owns shared cluster capabilities:

- ingress
- MetalLB
- cert-manager
- external-secrets
- OpenBao or another secret backend
- monitoring
- storage classes
- policy

## Layer 5: Workloads

`workloads` owns apps that can be added or removed without changing cluster foundations:

- game servers
- Home Assistant
- GitHub runners
- InfluxDB
- Authentik
- OpenLDAP
