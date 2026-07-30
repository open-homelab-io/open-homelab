# OpenBao

OpenBao is deployed by Argo CD from the official Helm chart in HA mode with integrated Raft storage.

The first deployment intentionally does not expose ingress or auto-unseal. Use `kubectl port-forward` for UI access and keep init/unseal material out of Git.

## First-Time Initialization

Run after the `openbao` Argo application has synced and the pods exist:

```bash
scripts/bootstrap-openbao.sh
```

The script writes init material to `.context/openbao/init.json`, unseals all three pods, joins followers to Raft, and prints the peer list without printing unseal keys or the root token.

Verify the cluster:

```bash
kubectl --kubeconfig clusters/production/talos/generated/kubeconfig \
  -n openbao get pods

kubectl --kubeconfig clusters/production/talos/generated/kubeconfig \
  -n openbao exec openbao-0 -- bao status
```

## UI Access

```bash
kubectl --kubeconfig clusters/production/talos/generated/kubeconfig \
  -n openbao port-forward openbao-0 8200:8200
```

## External Secrets Operator

After External Secrets Operator is installed, configure OpenBao Kubernetes auth for the GitOps-managed `ClusterSecretStore`:

```bash
scripts/bootstrap-openbao-external-secrets.sh
```

This creates:

- KV v2 secrets engine at `secret/`
- Kubernetes auth mount at `kubernetes/`
- `external-secrets` policy for `secret/data/*` and `secret/metadata/*`
- `external-secrets` role bound to service account `external-secrets` in namespace `external-secrets`
