###############################################################################
# Storage Module - GCP Variables
# Defines all input variables for Google Cloud Storage bucket
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

variable "bucket_name" {
  description = "Name for the GCS bucket (must be globally unique)"
  type        = string
  default     = ""

  validation {
    condition     = var.bucket_name == "" || can(regex("^[a-z0-9][a-z0-9._-]{1,220}[a-z0-9]$", var.bucket_name))
    error_message = "Bucket name must be 3-222 characters, lowercase alphanumeric with dots, hyphens, and underscores."
  }
}

variable "location" {
  description = "GCS bucket location (region, dual-region, or multi-region)"
  type        = string
  default     = "US"
}

variable "storage_class" {
  description = "Default storage class for the bucket"
  type        = string
  default     = "STANDARD"

  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "cors_origins" {
  description = "List of allowed CORS origins for frontend access"
  type        = list(string)
  default     = ["*"]
}

variable "lifecycle_rules_enabled" {
  description = "Enable lifecycle rules for automatic storage class transitions"
  type        = bool
  default     = true
}

variable "gke_service_account_email" {
  description = "Email of the GKE workload service account that needs bucket access"
  type        = string
  default     = ""
}

variable "labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
}
