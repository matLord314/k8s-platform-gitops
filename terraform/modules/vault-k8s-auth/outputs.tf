output "kv_mount_path" {
  description = "KV v2 mount External Secrets should use as spec.provider.vault.path."
  value       = vault_mount.kv.path
}

output "policy_name" {
  description = "Policy attached to the Kubernetes auth role."
  value       = vault_policy.external_secrets.name
}

output "kubernetes_auth_path" {
  description = "Kubernetes auth mount path."
  value       = vault_auth_backend.kubernetes.path
}

output "kubernetes_auth_role" {
  description = "Role name referenced by the ClusterSecretStore."
  value       = vault_kubernetes_auth_backend_role.external_secrets.role_name
}
