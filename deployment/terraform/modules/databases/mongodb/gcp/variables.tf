###############################################################################
# MongoDB Atlas Module - GCP Variables
# Defines all input variables for MongoDB Atlas cluster on GCP
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

variable "atlas_project_id" {
  description = "MongoDB Atlas project ID"
  type        = string

  validation {
    condition     = can(regex("^[a-f0-9]{24}$", var.atlas_project_id))
    error_message = "Atlas project ID must be a 24-character hexadecimal string."
  }
}

variable "atlas_org_id" {
  description = "MongoDB Atlas organization ID"
  type        = string

  validation {
    condition     = can(regex("^[a-f0-9]{24}$", var.atlas_org_id))
    error_message = "Atlas organization ID must be a 24-character hexadecimal string."
  }
}

variable "cluster_name" {
  description = "Name of the MongoDB Atlas cluster"
  type        = string
  default     = ""

  validation {
    condition     = var.cluster_name == "" || can(regex("^[a-zA-Z][a-zA-Z0-9-]{0,22}[a-zA-Z0-9]$", var.cluster_name))
    error_message = "Cluster name must be alphanumeric with hyphens, starting with a letter, max 24 characters."
  }
}

variable "instance_size" {
  description = "MongoDB Atlas instance tier (e.g., M10 for dev, M30 for prod)"
  type        = string
  default     = "M10"

  validation {
    condition     = contains(["M10", "M20", "M30", "M40", "M50", "M60", "M80"], var.instance_size)
    error_message = "Instance size must be one of: M10, M20, M30, M40, M50, M60, M80."
  }
}

variable "region" {
  description = "GCP region for the Atlas cluster (Atlas format, e.g., CENTRAL_US)"
  type        = string
  default     = "CENTRAL_US"
}

variable "disk_size_gb" {
  description = "Disk storage size in GB for the Atlas cluster"
  type        = number
  default     = 10

  validation {
    condition     = var.disk_size_gb >= 10 && var.disk_size_gb <= 4096
    error_message = "Disk size must be between 10 and 4096 GB."
  }
}

variable "cloud_backup_enabled" {
  description = "Enable cloud backup (continuous backup) for the cluster"
  type        = bool
  default     = true
}

variable "auto_scaling_enabled" {
  description = "Enable auto-scaling for compute and disk. Recommended for prod"
  type        = bool
  default     = false
}

variable "gcp_project_id" {
  description = "GCP project ID for VPC peering or Private Service Connect"
  type        = string
}

variable "network_name" {
  description = "Name of the GCP VPC network for private connectivity"
  type        = string
}

variable "database_user" {
  description = "Username for the MongoDB database user"
  type        = string
  default     = "pipeshub-app"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_-]{2,127}$", var.database_user))
    error_message = "Database username must start with a letter, 3-128 characters, alphanumeric with hyphens and underscores."
  }
}

variable "database_password" {
  description = "Password for the MongoDB database user"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.database_password) >= 8
    error_message = "Database password must be at least 8 characters long."
  }
}
