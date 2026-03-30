###############################################################################
# Secrets Module - AWS Variables
# Defines all input variables for AWS Secrets Manager, KMS,
# and External Secrets Operator
###############################################################################

variable "environment" {
  description = "Deployment environment (e.g., dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project, used for resource naming and tagging"
  type        = string
  default     = "pipeshub"
}

variable "secrets_map" {
  description = "Map of secret names to their values. If empty, secrets are expected to be pre-created"
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "kms_key_alias" {
  description = "Alias for the KMS key used to encrypt secrets"
  type        = string
  default     = ""
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider for IRSA"
  type        = string
}

variable "oidc_provider_url" {
  description = "URL of the EKS OIDC provider (without https:// prefix)"
  type        = string
}

variable "eks_namespace" {
  description = "Kubernetes namespace where External Secrets Operator will be deployed"
  type        = string
  default     = "external-secrets"
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
