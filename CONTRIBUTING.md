# Contributing

Thanks for improving `open-homelab`.

## Scope

Good contributions are usually one of:

- documentation fixes that make deployment clearer
- bug fixes for bootstrap scripts or manifests
- new platform capabilities behind clear configuration
- workload examples that are useful to more than one lab
- tests or validation scripts for risky automation

Keep personal lab values out of commits. Use placeholders such as `example.com`, `192.168.5.0/24`, and `admin@example.com` in shared docs and examples.

## Development Workflow

1. Fork or branch from `main`.
2. Make the smallest coherent change.
3. Run the relevant validation commands.
4. Update docs when behavior, configuration, or operations change.
5. Open a pull request with the deployment mode you tested.
6. Use a Conventional Commit-style squash message when merging, such as `fix: correct Talos bootstrap docs` or `feat: add workload example`.

## Validation

For Proxmox changes:

```bash
cd infra/proxmox
bun install
bun run get
bun run typecheck
bun run synth
```

For AWS changes:

```bash
cd infra/aws
bun install
bun run typecheck
bun run synth
```

For manifest-only changes:

```bash
kubectl kustomize platform >/dev/null
kubectl kustomize clusters/production/gitops >/dev/null
kubectl kustomize clusters/production/gitops/root >/dev/null
```

Some Helm values are validated by Argo CD at deploy time. Include the apps you synced and the resulting health status in the pull request.

## Pull Request Notes

Include:

- what changed
- why it changed
- whether you tested local/no-AWS, AWS state, AWS DNS, or docs-only
- any migration steps for existing users
- any new secrets, permissions, or cloud resources

## Releases

Releases are managed by Release Please from Conventional Commit messages on `main`. See [docs/release-process.md](docs/release-process.md).

## Secrets

Never commit real credentials, kubeconfigs, Talos secrets, Terraform state, OpenBao tokens, ACME account keys, private certificates, or personal hosted zone IDs.
