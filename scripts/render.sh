#!/usr/bin/env bash
# kustomize build and helm template into ./rendered
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${ROOT}/rendered"
K8S_VERSION="${KUBECONFORM_K8S_VERSION:-1.35.0}"

CERT_MANAGER_VERSION="v1.21.2"
INGRESS_NGINX_VERSION="4.15.1"
KPS_VERSION="92.1.0"
ESO_VERSION="2.12.0"
VAULT_VERSION="0.34.1"
LOKI_VERSION="7.3.0"

require_pin() {
  local file="$1"
  local version="$2"
  if ! grep -q "targetRevision: ${version}$" "${file}"; then
    echo "pinned version ${version} not found in ${file}" >&2
    exit 1
  fi
}

require_pin "${ROOT}/apps/base/cert-manager.yaml" "${CERT_MANAGER_VERSION}"
require_pin "${ROOT}/apps/base/ingress-nginx.yaml" "${INGRESS_NGINX_VERSION}"
require_pin "${ROOT}/apps/base/kube-prometheus-stack.yaml" "${KPS_VERSION}"
require_pin "${ROOT}/apps/base/external-secrets.yaml" "${ESO_VERSION}"
require_pin "${ROOT}/apps/base/vault.yaml" "${VAULT_VERSION}"
require_pin "${ROOT}/apps/optional/loki.yaml" "${LOKI_VERSION}"

helm repo add jetstack https://charts.jetstack.io --force-update >/dev/null
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update >/dev/null
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update >/dev/null
helm repo add external-secrets https://charts.external-secrets.io --force-update >/dev/null
helm repo add hashicorp https://helm.releases.hashicorp.com --force-update >/dev/null
helm repo add grafana https://grafana.github.io/helm-charts --force-update >/dev/null
helm repo update >/dev/null

rm -rf "${OUT}"
mkdir -p "${OUT}/demo-app" "${OUT}/apps" "${OUT}/platform" "${OUT}/helm"

helm template demo-app "${ROOT}/charts/demo-app" \
  --namespace demo-app \
  --values "${ROOT}/charts/demo-app/values-dev.yaml" \
  > "${OUT}/demo-app/dev.yaml"
helm template demo-app "${ROOT}/charts/demo-app" \
  --namespace demo-app \
  --values "${ROOT}/charts/demo-app/values-prod.yaml" \
  > "${OUT}/demo-app/prod.yaml"

kustomize build "${ROOT}/apps/overlays/dev" > "${OUT}/apps/dev.yaml"
kustomize build "${ROOT}/apps/overlays/prod" > "${OUT}/apps/prod.yaml"
kustomize build "${ROOT}/platform/cert-manager/config" > "${OUT}/platform/cert-manager.yaml"
kustomize build "${ROOT}/platform/monitoring" > "${OUT}/platform/monitoring.yaml"
kustomize build "${ROOT}/platform/external-secrets/config" > "${OUT}/platform/external-secrets.yaml"
kustomize build "${ROOT}/platform/vault/config" > "${OUT}/platform/vault.yaml"

helm template cert-manager jetstack/cert-manager \
  --version "${CERT_MANAGER_VERSION}" \
  --namespace cert-manager \
  --values "${ROOT}/platform/cert-manager/values.yaml" \
  > "${OUT}/helm/cert-manager.yaml"
helm template ingress-nginx ingress-nginx/ingress-nginx \
  --version "${INGRESS_NGINX_VERSION}" \
  --namespace ingress-nginx \
  --values "${ROOT}/platform/ingress-nginx/values-dev.yaml" \
  > "${OUT}/helm/ingress-nginx-dev.yaml"
helm template ingress-nginx ingress-nginx/ingress-nginx \
  --version "${INGRESS_NGINX_VERSION}" \
  --namespace ingress-nginx \
  --values "${ROOT}/platform/ingress-nginx/values-prod.yaml" \
  > "${OUT}/helm/ingress-nginx-prod.yaml"
helm template kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --version "${KPS_VERSION}" \
  --namespace monitoring \
  --values "${ROOT}/platform/kube-prometheus-stack/values-dev.yaml" \
  > "${OUT}/helm/kube-prometheus-stack-dev.yaml"
helm template kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --version "${KPS_VERSION}" \
  --namespace monitoring \
  --values "${ROOT}/platform/kube-prometheus-stack/values-prod.yaml" \
  > "${OUT}/helm/kube-prometheus-stack-prod.yaml"
helm template external-secrets external-secrets/external-secrets \
  --version "${ESO_VERSION}" \
  --namespace external-secrets \
  --values "${ROOT}/platform/external-secrets/values.yaml" \
  > "${OUT}/helm/external-secrets.yaml"
helm template vault hashicorp/vault \
  --version "${VAULT_VERSION}" \
  --namespace vault \
  --values "${ROOT}/platform/vault/values-dev.yaml" \
  > "${OUT}/helm/vault-dev.yaml"
helm template vault hashicorp/vault \
  --version "${VAULT_VERSION}" \
  --namespace vault \
  --values "${ROOT}/platform/vault/values-prod.yaml" \
  > "${OUT}/helm/vault-prod.yaml"
helm template loki grafana/loki \
  --version "${LOKI_VERSION}" \
  --namespace logging \
  --values "${ROOT}/platform/loki/values.yaml" \
  > "${OUT}/helm/loki.yaml"

cp "${ROOT}/clusters/dev/root-application.yaml" "${OUT}/apps/root-dev.yaml"
cp "${ROOT}/clusters/prod/root-application.yaml" "${OUT}/apps/root-prod.yaml"
cp "${ROOT}/apps/optional/loki.yaml" "${OUT}/apps/loki.yaml"

echo "rendered manifests in ${OUT} (kubernetes ${K8S_VERSION})"
