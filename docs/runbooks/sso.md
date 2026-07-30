# Platform SSO

Keycloak is the identity provider for platform tools.

| App | URL | Integration |
| --- | --- | --- |
| Argo CD | `https://argo.lab.example.com` | Native OIDC |
| OpenBao | `https://bao.lab.example.com` | Native OIDC auth method |
| Longhorn | `https://longhorn.lab.example.com` | oauth2-proxy in front of Longhorn UI |
| Grafana | `https://grafana.lab.example.com` | Native generic OAuth |

The first human admin from `.env` is the admin principal for these apps. In the sample `.env`, that is `admin@example.com`.

## Bootstrap

Run this after OpenBao and Keycloak are healthy:

```bash
scripts/bootstrap-keycloak-secrets.sh
scripts/bootstrap-openbao-keycloak-oidc.sh
```

The first script seeds the OIDC client secrets in OpenBao. Keycloak's bootstrap Job creates or updates the clients, including Grafana. The second script enables OpenBao's OIDC auth method and maps the first admin email to the OpenBao `admin` policy.

## Notes

- Argo CD keeps the local `admin` user enabled as break-glass access while the cluster is bootstrapping.
- Longhorn has no native OIDC login in this deployment path, so only the oauth2-proxy ingress is exposed.
- OpenBao root token and unseal material remain local recovery material under `.context/openbao/init.json`.
