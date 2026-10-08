# Vault Kubernetes auth

Creates a KV v2 mount at `platform`, a policy that can read `platform/data/demo-app/*`, and a Kubernetes auth role for the `external-secrets` service account.

Secret values are not in this module. They would land in state. Write them with the CLI after apply.

The dev Vault chart already has KV at `secret/`. This module uses `platform` so it does not collide. The ClusterSecretStore in `platform/external-secrets/config` uses the same path.

Bootstrap the cluster first. You need the `vault-auth` service account and its `system:auth-delegator` binding.

```bash
kubectl -n vault port-forward svc/vault 8200:8200
```

In another shell. The dev server token is `root`.

```bash
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=root

CA="$(kubectl config view --raw --minify --flatten \
  -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d)"
JWT="$(kubectl -n vault create token vault-auth --audience=vault --duration=1h)"

cd terraform/envs/dev
terraform init
terraform apply \
  -var="kubernetes_host=https://kubernetes.default.svc" \
  -var="kubernetes_ca_cert=${CA}" \
  -var="token_reviewer_jwt=${JWT}"
```

That JWT expires. Mint another one before the next apply. `disable_iss_validation` defaults to true in `envs/dev` because kind's issuer does not match the in-cluster API address.

```bash
vault kv put platform/demo-app/config api-token=local-demo
```

External Secrets projects `api-token` into `demo-app-secrets`. The sample pod mounts it only when the Secret exists.

`modules/vault-k8s-auth` is the module. `envs/dev` calls it for the kind dev server. `terraform validate` does not need a live Vault.
