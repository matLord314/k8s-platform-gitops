#!/usr/bin/env bash
# pin the CLIs used by make lint (github actions)
set -euo pipefail

HELM_VERSION="${HELM_VERSION:-v3.19.0}"
TERRAFORM_VERSION="${TERRAFORM_VERSION:-1.16.5}"
KUSTOMIZE_VERSION="${KUSTOMIZE_VERSION:-v5.7.1}"
KUBECONFORM_VERSION="${KUBECONFORM_VERSION:-v0.8.0}"
RUFF_VERSION="${RUFF_VERSION:-0.16.10}"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

sudo apt-get update
sudo apt-get install -y --no-install-recommends ca-certificates curl unzip shellcheck yamllint

curl -fsSL -o "${tmpdir}/helm.tgz" \
  "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz"
tar -C "${tmpdir}" -xzf "${tmpdir}/helm.tgz"
sudo install -m 0755 "${tmpdir}/linux-amd64/helm" /usr/local/bin/helm

curl -fsSL -o "${tmpdir}/terraform.zip" \
  "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
unzip -o "${tmpdir}/terraform.zip" -d "${tmpdir}"
sudo install -m 0755 "${tmpdir}/terraform" /usr/local/bin/terraform

curl -fsSL -o "${tmpdir}/kustomize.tgz" \
  "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${KUSTOMIZE_VERSION}/kustomize_${KUSTOMIZE_VERSION}_linux_amd64.tar.gz"
tar -C "${tmpdir}" -xzf "${tmpdir}/kustomize.tgz"
sudo install -m 0755 "${tmpdir}/kustomize" /usr/local/bin/kustomize

curl -fsSL -o "${tmpdir}/kubeconform.tgz" \
  "https://github.com/yannh/kubeconform/releases/download/${KUBECONFORM_VERSION}/kubeconform-linux-amd64.tar.gz"
tar -C "${tmpdir}" -xzf "${tmpdir}/kubeconform.tgz"
sudo install -m 0755 "${tmpdir}/kubeconform" /usr/local/bin/kubeconform

python3 -m pip install --user --break-system-packages "ruff==${RUFF_VERSION}"
if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "${HOME}/.local/bin" >> "${GITHUB_PATH}"
fi
