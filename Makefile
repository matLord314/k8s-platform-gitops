SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c
export PATH := $(HOME)/.local/bin:$(PATH)

CLUSTER_NAME ?= platform
ENVIRONMENT ?= dev
KIND_CONFIG := deploy/kind/cluster.yaml
KUBECONFORM_K8S_VERSION ?= 1.35.0

.DEFAULT_GOAL := help

.PHONY: help cluster-up bootstrap down lint render kubeconform helm-lint yamllint terraform python shell

help:
	@printf '%s\n' \
	  'cluster-up   create the kind cluster' \
	  'bootstrap    install argocd and apply the $(ENVIRONMENT) root app' \
	  'lint         yamllint, helm, kubeconform, terraform, ruff, shellcheck' \
	  'render       write manifests under ./rendered' \
	  'down         delete the kind cluster'

cluster-up:
	kind create cluster --name $(CLUSTER_NAME) --config $(KIND_CONFIG)

bootstrap:
	./scripts/bootstrap.sh $(ENVIRONMENT)

down:
	kind delete cluster --name $(CLUSTER_NAME)

lint: yamllint helm-lint kubeconform terraform python shell

render:
	KUBECONFORM_K8S_VERSION=$(KUBECONFORM_K8S_VERSION) ./scripts/render.sh

helm-lint:
	helm lint charts/demo-app
	helm lint charts/demo-app --values charts/demo-app/values-dev.yaml
	helm lint charts/demo-app --values charts/demo-app/values-prod.yaml

yamllint:
	yamllint .

kubeconform: render
	kubeconform -summary -strict \
	  -kubernetes-version $(KUBECONFORM_K8S_VERSION) \
	  -skip CustomResourceDefinition \
	  -schema-location default \
	  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
	  rendered/demo-app/*.yaml \
	  rendered/apps/*.yaml \
	  rendered/platform/*.yaml \
	  rendered/helm/*.yaml

terraform:
	terraform fmt -check -recursive terraform
	terraform -chdir=terraform/envs/dev init -backend=false -input=false
	terraform -chdir=terraform/envs/dev validate

python:
	ruff check scripts/rightsizing.py
	python3 scripts/rightsizing.py --self-test

shell:
	shellcheck scripts/bootstrap.sh scripts/render.sh scripts/install-ci-tools.sh
