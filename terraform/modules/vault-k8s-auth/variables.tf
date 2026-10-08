variable "kv_mount_path" {
  type        = string
  description = "Path of the KV version 2 mount External Secrets will read."
  default     = "platform"
}

variable "policy_name" {
  type        = string
  description = "Name of the policy granted to the External Secrets role."
  default     = "external-secrets"
}

variable "kubernetes_auth_path" {
  type        = string
  description = "Mount path of the Kubernetes auth backend."
  default     = "kubernetes"
}

variable "role_name" {
  type        = string
  description = "Kubernetes auth role assumed by External Secrets."
  default     = "external-secrets"
}

variable "bound_service_account_names" {
  type        = set(string)
  description = "Service accounts allowed to authenticate as this role."
  default     = ["external-secrets"]
}

variable "bound_service_account_namespaces" {
  type        = set(string)
  description = "Namespaces of the bound service accounts."
  default     = ["external-secrets"]
}

variable "token_ttl" {
  type        = number
  description = "TTL in seconds for tokens issued to External Secrets."
  default     = 3600
}

variable "token_audience" {
  type        = string
  description = "JWT audience. Vault 1.21+ checks this."
  default     = "vault"
}

variable "kubernetes_host" {
  type        = string
  description = "Kubernetes API address Vault uses for TokenReview."
}

variable "kubernetes_ca_cert" {
  type        = string
  description = "PEM-encoded CA certificate for the Kubernetes API."
}

variable "token_reviewer_jwt" {
  type        = string
  description = "TokenReview JWT. Do not commit it."
  sensitive   = true
}

variable "disable_iss_validation" {
  type        = bool
  description = "Skip iss checks. kind needs this when the issuer and kubernetes_host differ."
  default     = false
}
