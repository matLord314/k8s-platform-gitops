output "kv_mount_path" {
  description = "KV v2 mount created for External Secrets."
  value       = module.vault_k8s_auth.kv_mount_path
}

output "kubernetes_auth_role" {
  description = "Kubernetes auth role bound to the external-secrets service account."
  value       = module.vault_k8s_auth.kubernetes_auth_role
}
