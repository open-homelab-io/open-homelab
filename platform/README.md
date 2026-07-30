# Platform

Cluster-wide platform capabilities live here.

Included platform capabilities:

- MetalLB with the existing load-balancer pools.
- Traefik ingress controller at `192.168.5.46`.
- Longhorn distributed block storage.
- cert-manager without a DNS provider by default. The no-AWS path does not create ClusterIssuers.
- No ExternalDNS, Route53, or IAM Roles Anywhere in the default GitOps path.
- Optional Route53 DNS-01 and ExternalDNS through IAM Roles Anywhere via the AWS-enabled `clusters/production/gitops` overlay.
- External Secrets Operator wired to OpenBao through Kubernetes auth.
- OpenBao secret backend with Longhorn-backed Raft storage.
- Keycloak-backed SSO for platform tools.
- LGTM observability: Grafana, Loki, Tempo, Mimir, and Grafana k8s-monitoring/Alloy collectors.

The default local access model is:

```text
local DNS or /etc/hosts -> 192.168.5.46 -> Traefik -> app ingress
```

Publicly trusted certificates are not expected unless the optional AWS DNS automation path is enabled.
