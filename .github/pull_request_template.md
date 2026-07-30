## Summary

- 

## Deployment Mode Tested

- [ ] docs-only
- [ ] local/no-AWS
- [ ] AWS state
- [ ] AWS DNS

## Validation

- [ ] `cd infra/proxmox && bun run typecheck && bun run synth`
- [ ] `cd infra/aws && bun run typecheck && bun run synth`
- [ ] `kubectl kustomize platform`
- [ ] `kubectl kustomize clusters/production/gitops`
- [ ] `kubectl kustomize clusters/production/gitops/root`
- [ ] Argo CD sync checked

## Notes

Mention any new secrets, permissions, cloud resources, migration steps, or known gaps.
