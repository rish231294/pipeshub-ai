###############################################################################
# Storage Module - Azure (Storage Account + Blob Container) Variables
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

variable "storage_account_name" {
  description = "Name of the Azure Storage Account. Must be globally unique, 3-24 lowercase alphanumeric chars. If not provided, one will be generated"
  type        = string
  default     = ""

  validation {
    condition     = var.storage_account_name == "" || can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage account name must be 3-24 characters, lowercase letters and numbers only."
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

variable "database_subnet_id" {
  description = "ID of the database subnet for the private endpoint"
  type        = string
}

variable "account_replication_type" {
  description = "Storage account replication type: LRS (dev), GRS (prod), ZRS, RAGRS, RAGZRS, GZRS"
  type        = string
  default     = "LRS"

  validation {
    condition     = contains(["LRS", "GRS", "ZRS", "RAGRS", "RAGZRS", "GZRS"], var.account_replication_type)
    error_message = "Account replication type must be one of: LRS, GRS, ZRS, RAGRS, RAGZRS, GZRS."
  }
}

variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS on the blob service (e.g., frontend URLs)"
  type        = list(string)
  default     = []
}

variable "lifecycle_rules_enabled" {
  description = "Enable lifecycle management rules for blob storage (cool after 90 days, archive after 365 days)"
  type        = bool
  default     = true
}

variable "aks_kubelet_identity_object_id" {
  description = "Object ID of the AKS kubelet managed identity for storage access via RBAC"
  type        = string
  default     = ""
}

variable "enable_private_endpoint" {
  description = "Enable private endpoint for the storage account"
  type        = bool
  default     = true
}

variable "container_name" {
  description = "Name of the blob container for document uploads"
  type        = string
  default     = "documents"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.container_name))
    error_message = "Container name must be 3-63 characters, lowercase letters, numbers, and hyphens."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
