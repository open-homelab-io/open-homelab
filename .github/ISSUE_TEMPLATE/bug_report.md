---
name: Bug report
about: Report a reproducible deployment or operations bug
title: ""
labels: bug
assignees: ""
---

## Summary

What failed?

## Deployment Mode

- local/no-AWS
- AWS state
- AWS DNS
- other:

## Environment

- Proxmox version:
- Talos version:
- Kubernetes version:
- Node count and roles:
- Network CIDR:
- Relevant hardware/storage:

## Steps To Reproduce

1.
2.
3.

## Expected Behavior

What should have happened?

## Actual Behavior

What happened instead?

## Logs Or Output

Paste only non-secret output. Redact tokens, kubeconfigs, private keys, hosted zone IDs if needed, and public IPs if you do not want them shared.

```text

```

## Validation Already Run

- [ ] `bun run typecheck`
- [ ] `bun run synth`
- [ ] `kubectl kustomize`
- [ ] Argo CD sync checked
- [ ] Other:
