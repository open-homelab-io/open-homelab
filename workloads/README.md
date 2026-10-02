# Workloads

Apps that are not required for cluster operation live here.

Planned and example workload targets:

- Factorio
- Minecraft Java
- Minecraft Bedrock
- Palworld
- Satisfactory
- Home Assistant
- InfluxDB
- GitHub self-hosted runners
- OpenLDAP, if not part of the identity platform

## MetalLB LoadBalancer Services

Workload examples that expose a `Service` with `type: LoadBalancer` should
select the example address pool with the current MetalLB annotation:

```yaml
metadata:
  annotations:
    metallb.io/address-pool: homelab-lbs
```

Avoid the deprecated `metallb.universe.tf/ip-allocated-from-pool` annotation in
new manifests.
