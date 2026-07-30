#!/usr/bin/env bash
set -euo pipefail

# Installs Cilium as the cluster CNI immediately after `talosctl bootstrap`.
#
# Talos is configured with cni.name=none and proxy.disabled=true, so on a fresh
# cluster the nodes stay NotReady and no pod networking exists until a CNI is
# present. Argo CD cannot schedule pods before that, so Cilium must be installed
# out-of-band here, before scripts/bootstrap-argocd.sh runs.
#
# Argo CD later adopts this same Helm release (same name + namespace) via
# clusters/production/gitops/root/cilium.yaml for ongoing lifecycle management.

KUBECONFIG_PATH="${KUBECONFIG:-clusters/production/talos/generated/kubeconfig}"
CILIUM_NAMESPACE="${CILIUM_NAMESPACE:-kube-system}"
CILIUM_CHART_VERSION="${CILIUM_CHART_VERSION:-1.19.6}"
VALUES_FILE="${VALUES_FILE:-platform/cilium/values.yaml}"

if [[ ! -f "${KUBECONFIG_PATH}" ]]; then
  echo "Kubeconfig not found at ${KUBECONFIG_PATH}" >&2
  exit 1
fi

if [[ ! -f "${VALUES_FILE}" ]]; then
  echo "Cilium values not found at ${VALUES_FILE}" >&2
  exit 1
fi

helm repo add cilium https://helm.cilium.io/ >/dev/null 2>&1 || true
helm repo update cilium

KUBECONFIG="${KUBECONFIG_PATH}" helm upgrade --install cilium cilium/cilium \
  --version "${CILIUM_CHART_VERSION}" \
  --namespace "${CILIUM_NAMESPACE}" \
  -f "${VALUES_FILE}" \
  --wait

echo "Cilium ${CILIUM_CHART_VERSION} installed. Waiting for nodes to become Ready..."
KUBECONFIG="${KUBECONFIG_PATH}" kubectl wait --for=condition=Ready nodes --all --timeout=300s || true
KUBECONFIG="${KUBECONFIG_PATH}" kubectl -n "${CILIUM_NAMESPACE}" get pods -l k8s-app=cilium -o wide
