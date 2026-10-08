module "vault_k8s_auth" {
  source = "../../modules/vault-k8s-auth"

  kubernetes_host        = var.kubernetes_host
  kubernetes_ca_cert     = var.kubernetes_ca_cert
  token_reviewer_jwt     = var.token_reviewer_jwt
  disable_iss_validation = var.disable_iss_validation
}
