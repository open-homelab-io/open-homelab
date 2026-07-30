#!/usr/bin/env bash
set -euo pipefail

KUBECONFIG_PATH="${KUBECONFIG:-clusters/production/talos/generated/kubeconfig}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
ARGOCD_CHART_VERSION="${ARGOCD_CHART_VERSION:-10.2.1}"
REPO_URL="${REPO_URL:-https://github.com/open-homelab-io/open-homelab.git}"
REPO_SECRET_NAME="${REPO_SECRET_NAME:-open-homelab-repo}"
GITOPS_ROOT_PATH="${GITOPS_ROOT_PATH:-clusters/production/gitops/root}"

if [[ "${GITOPS_ROOT_PATH}" == "clusters/production/gitops" && "${ALLOW_AWS_GITOPS:-0}" != "1" ]]; then
  cat >&2 <<'EOF'
Refusing to bootstrap the AWS-enabled GitOps path.

The default no-AWS path is clusters/production/gitops/root.
Set ALLOW_AWS_GITOPS=1 only if you intentionally want Route53 issuers and ExternalDNS.
EOF
  exit 1
fi

if [[ ! -f "${KUBECONFIG_PATH}" ]]; then
  echo "Kubeconfig not found at ${KUBECONFIG_PATH}" >&2
  exit 1
fi

helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update argo

KUBECONFIG="${KUBECONFIG_PATH}" helm upgrade --install argocd argo/argo-cd \
  --version "${ARGOCD_CHART_VERSION}" \
  --namespace "${ARGOCD_NAMESPACE}" \
  --create-namespace \
  -f platform/argocd/values.yaml

token="${GITHUB_TOKEN:-}"
if [[ -z "${token}" ]] && command -v gh >/dev/null 2>&1; then
  token="$(gh auth token 2>/dev/null || true)"
fi

if [[ -n "${token}" ]]; then
  KUBECONFIG="${KUBECONFIG_PATH}" kubectl -n "${ARGOCD_NAMESPACE}" create secret generic "${REPO_SECRET_NAME}" \
    --from-literal=type=git \
    --from-literal=url="${REPO_URL}" \
    --from-literal=username=x-access-token \
    --from-literal=password="${token}" \
    --dry-run=client -o yaml | KUBECONFIG="${KUBECONFIG_PATH}" kubectl apply -f -

  KUBECONFIG="${KUBECONFIG_PATH}" kubectl -n "${ARGOCD_NAMESPACE}" label secret "${REPO_SECRET_NAME}" \
    argocd.argoproj.io/secret-type=repository --overwrite
else
  echo "No GitHub token found; assuming ${REPO_URL} is public."
fi

KUBECONFIG="${KUBECONFIG_PATH}" kubectl apply -f clusters/production/gitops/root-app.yaml
KUBECONFIG="${KUBECONFIG_PATH}" kubectl -n "${ARGOCD_NAMESPACE}" patch application homelab-root \
  --type merge \
  -p "{\"spec\":{\"source\":{\"repoURL\":\"${REPO_URL}\",\"path\":\"${GITOPS_ROOT_PATH}\"}}}"
KUBECONFIG="${KUBECONFIG_PATH}" kubectl -n "${ARGOCD_NAMESPACE}" annotate application homelab-root \
  argocd.argoproj.io/refresh=hard --overwrite

KUBECONFIG="${KUBECONFIG_PATH}" kubectl -n "${ARGOCD_NAMESPACE}" get applications.argoproj.io -o wide
