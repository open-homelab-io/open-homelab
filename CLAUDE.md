# Claude Guidance

This repo is a public, code-first homelab template. Help users bring it online safely and keep personal lab values out of commits.

## Skills

Use repo-local Claude skills when the task matches:

- `.claude/skills/open-homelab-local-bringup/SKILL.md`: default local/no-AWS deployment, bootstrap, validation, and recovery.
- `.claude/skills/open-homelab-aws-bringup/SKILL.md`: optional S3 OpenTofu state, Route53 DNS automation, IAM Roles Anywhere, ExternalDNS, and public ACME certificates.

## First Docs To Read

- `README.md`
- `docs/getting-started.md`
- `docs/deployment-modes.md`
- `docs/configuration.md`
- `docs/operations.md`

## Deployment Defaults

Default to local/no-AWS unless the user explicitly asks for AWS:

- local OpenTofu state
- Proxmox VMs
- Talos Kubernetes
- Cilium
- Argo CD default root path: `clusters/production/gitops/root`
- local DNS or `/etc/hosts`
- no Route53, ExternalDNS, IAM Roles Anywhere, or public ACME certificates

AWS is opt-in:

- `AWS_OPENTOFU_STATE_ENABLED=1` for S3 OpenTofu state
- `AWS_DNS_AUTOMATION_ENABLED=1` for Route53, IAM Roles Anywhere, ExternalDNS, and DNS-01 certificates
- AWS-enabled GitOps path requires `ALLOW_AWS_GITOPS=1 GITOPS_ROOT_PATH=clusters/production/gitops`

## Secret Handling

Never print or commit:

- `.env`
- Proxmox API tokens
- AWS credentials
- Talos `secrets.yaml`
- generated kubeconfigs or talosconfigs
- OpenTofu state
- OpenBao root tokens, unseal keys, recovery keys, or generated app secrets
- IAM Roles Anywhere private keys or certificates

Placeholders such as `example.com`, `admin@example.com`, `Z00000000000000000000`, and `user@pam!token-id=token-secret` are documentation examples only.

## Validation

Use the narrowest relevant validation:

```bash
cd infra/proxmox
bun run typecheck
bun run synth
```

```bash
cd infra/aws
bun run typecheck
bun run synth
```

```bash
kubectl kustomize platform
kubectl kustomize clusters/production/gitops
kubectl kustomize clusters/production/gitops/root
```
