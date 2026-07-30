# Keycloak

Keycloak replaces Authentik as the homelab identity provider and keeps the existing identity hostname:

```text
https://auth.lab.example.com
```

The deployment uses:

- CloudNativePG for the Keycloak PostgreSQL database.
- Longhorn-backed PostgreSQL volumes.
- OpenBao plus External Secrets Operator for database and bootstrap admin credentials.
- The official Keycloak Operator manifests pinned at `26.7.0`.
- Traefik edge TLS through cert-manager's `letsencrypt-prod` issuer.

## Bootstrap Secrets

Before the `keycloak` Argo application can become healthy, seed the required credentials into OpenBao:

```bash
scripts/bootstrap-keycloak-secrets.sh
```

The script creates these KV v2 paths if they do not already exist:

- `secret/platform/keycloak/database`
- `secret/platform/keycloak/admin`
- `secret/platform/keycloak/users/first-admin`
- `secret/platform/keycloak/clients/argocd`
- `secret/platform/keycloak/clients/openbao`
- `secret/platform/keycloak/clients/longhorn`
- `secret/platform/longhorn/oauth2-proxy`

Set the first human admin in `.env` before running the script:

```bash
KEYCLOAK_FIRST_ADMIN_USERNAME=admin
KEYCLOAK_FIRST_ADMIN_EMAIL=admin@example.com
KEYCLOAK_FIRST_ADMIN_TEMP_PASSWORD=
KEYCLOAK_FIRST_ADMIN_FIRST_NAME=Open
KEYCLOAK_FIRST_ADMIN_LAST_NAME=Homelab
```

If `KEYCLOAK_FIRST_ADMIN_TEMP_PASSWORD` is empty, the script generates one and stores it in OpenBao. The GitOps-managed bootstrap Job creates or updates that user, grants the `admin` role in the `master` realm, and marks the password temporary so Keycloak forces a reset on first login.

The same Job also creates the Keycloak OIDC clients used by Argo CD, OpenBao, and Longhorn.

It does not print generated passwords. To intentionally rotate the OpenBao values later:

```bash
KEYCLOAK_ROTATE_SECRETS=true scripts/bootstrap-keycloak-secrets.sh
```

Do not rotate the database credentials without planning a matching PostgreSQL user password change.

## Verify

```bash
kubectl --kubeconfig clusters/production/talos/generated/kubeconfig \
  -n argocd get applications cloudnative-pg keycloak-operator keycloak

kubectl --kubeconfig clusters/production/talos/generated/kubeconfig \
  -n keycloak get externalsecrets,secrets,clusters.postgresql.cnpg.io,pods,jobs,ingress
```

When the ingress is ready:

```bash
curl -I https://auth.lab.example.com
```

## Admin Login

The bootstrap admin username defaults to `admin`. Read the generated password only when you need to sign in:

```bash
kubectl --kubeconfig clusters/production/talos/generated/kubeconfig \
  -n keycloak get secret keycloak-bootstrap-admin \
  -o jsonpath='{.data.password}' | base64 --decode
```

For normal administration, use the first human admin account instead. Read its temporary password only when you need the first login:

```bash
kubectl --kubeconfig clusters/production/talos/generated/kubeconfig \
  -n keycloak get secret keycloak-first-admin \
  -o jsonpath='{.data.temporary_password}' | base64 --decode
```
