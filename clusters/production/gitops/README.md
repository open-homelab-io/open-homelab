# GitOps Bootstrap

This directory should contain only the minimum ArgoCD bootstrap entrypoint.

Recommended shape:

- Install ArgoCD using upstream chart references and local values.
- Point ArgoCD at this repo.
- Sync a single app-of-apps or ApplicationSet that fans out to `platform` and `workloads`.

Keep cluster foundations in `platform`; keep user workloads in `workloads`.

Initial entrypoint:

```bash
scripts/bootstrap-argocd.sh
```

The default root path, `clusters/production/gitops/root`, does not include AWS-backed DNS automation. Use the AWS-enabled path when this cluster should include Route53 cert-manager issuers and ExternalDNS:

```bash
ALLOW_AWS_GITOPS=1 GITOPS_ROOT_PATH=clusters/production/gitops scripts/bootstrap-argocd.sh
```

The root app currently syncs Argo CD itself. Platform and workload child apps are staged in this directory but intentionally not included until their first real slices are ready.

The repository is private, so the bootstrap script creates an Argo CD repository secret from `GITHUB_TOKEN` or `gh auth token`. The token is live cluster state and must not be committed.
