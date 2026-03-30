###############################################################################
# Secrets Module - Azure (Key Vault + External Secrets Operator) Variables
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

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,28}[a-z0-9]$", var.project_name))
    error_message = "Project name must be 3-30 characters, lowercase alphanumeric with hyphens, starting with a letter."
  }
}

variable "key_vault_name" {
  description = "Name of the Azure Key Vault. If not provided, one will be generated. Must be globally unique (3-24 chars)"
  type        = string
  default     = ""

  validation {
    condition     = var.key_vault_name == "" || can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$", var.key_vault_name))
    error_message = "Key Vault name must be 3-24 characters, alphanumeric with hyphens, starting and ending with alphanumeric."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "eastus"
}

variable "tenant_id" {
  description = "Azure AD tenant ID for Key Vault access policies"
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.tenant_id))
    error_message = "Tenant ID must be a valid UUID."
  }
}

variable "aks_kubelet_identity_object_id" {
  description = "Object ID of the AKS kubelet managed identity for Key Vault access"
  type        = string
}

variable "oidc_issuer_url" {
  description = "OIDC issuer URL from the AKS cluster for workload identity federation"
  type        = string
}

variable "eso_namespace" {
  description = "Kubernetes namespace where External Secrets Operator will be deployed"
  type        = string
  default     = "external-secrets"
}

variable "eso_service_account_name" {
  description = "Name of the Kubernetes service account for External Secrets Operator"
  type        = string
  default     = "external-secrets-sa"
}

variable "secrets_map" {
  description = "Map of secret names to their values to store in Key Vault"
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
