#!/usr/bin/env bash
# install pinned argocd, then apply clusters/<env>/root-application.yaml
set -euo pipefail

ARGOCD_VERSION="${ARGOCD_VERSION:-v3.5.4}"
ENVIRONMENT="${1:-${ENVIRONMENT:-dev}}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT_APP="${ROOT}/clusters/${ENVIRONMENT}/root-application.yaml"
INSTALL_URL="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

if [[ ! -f "${ROOT_APP}" ]]; then
  echo "unknown environment: ${ENVIRONMENT}" >&2
  exit 1
fi

if ! kubectl get namespace argocd >/dev/null 2>&1; then
  kubectl create namespace argocd
fi

kubectl apply \
  --namespace argocd \
  --server-side \
  --force-conflicts \
  --filename "${INSTALL_URL}"

kubectl --namespace argocd rollout status deployment/argocd-server --timeout=300s
kubectl apply --filename "${ROOT_APP}"

cat <<EOF
Argo CD ${ARGOCD_VERSION} is installed.
The ${ENVIRONMENT} root Application is applied.
Read the initial admin password with:
  kubectl --namespace argocd get secret argocd-initial-admin-secret \\
    -o jsonpath='{.data.password}' | base64 --decode; echo
EOF
