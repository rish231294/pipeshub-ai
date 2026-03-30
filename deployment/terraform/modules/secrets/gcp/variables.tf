###############################################################################
# Secrets Module - GCP Variables
# Defines all input variables for Secret Manager and External Secrets Operator
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
  description = "Name of the project, used for resource naming and labeling"
  type        = string
  default     = "pipeshub"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,28}[a-z0-9]$", var.project_name))
    error_message = "Project name must be 3-30 characters, lowercase alphanumeric with hyphens, starting with a letter."
  }
}

variable "project_id" {
  description = "GCP project ID where resources will be created"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, lowercase alphanumeric with hyphens."
  }
}

variable "secrets_map" {
  description = "Map of secret names to their values. Keys become Secret Manager secret IDs"
  type        = map(string)
  sensitive   = true
  default     = {}
}

variable "gke_service_account_email" {
  description = "Email of the GKE node pool or workload service account that needs secret access"
  type        = string
  default     = ""
}

variable "workload_identity_pool" {
  description = "Workload Identity pool for the GKE cluster (PROJECT_ID.svc.id.goog)"
  type        = string
  default     = ""
}

variable "namespace" {
  description = "Kubernetes namespace for External Secrets Operator"
  type        = string
  default     = "external-secrets"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.namespace))
    error_message = "Namespace must be lowercase alphanumeric with hyphens, starting with a letter, max 63 characters."
  }
}

variable "labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
}
