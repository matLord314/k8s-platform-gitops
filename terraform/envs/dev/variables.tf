variable "kubernetes_host" {
  type        = string
  description = "Kubernetes API address reachable from the Vault pod."
}

variable "kubernetes_ca_cert" {
  type        = string
  description = "PEM-encoded Kubernetes API CA certificate."
}

variable "token_reviewer_jwt" {
  type        = string
  description = "vault-auth JWT for TokenReview. Do not commit it."
  sensitive   = true
}

variable "disable_iss_validation" {
  type        = bool
  description = "True here. On kind the issuer does not match the API host."
  default     = true
}
