###############################################################################
# Redis Module - GCP Variables
# Defines all input variables for Cloud Memorystore for Redis
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

variable "instance_name" {
  description = "Name for the Redis instance"
  type        = string
  default     = ""

  validation {
    condition     = var.instance_name == "" || can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", var.instance_name))
    error_message = "Instance name must be lowercase alphanumeric with hyphens, starting with a letter, max 40 characters."
  }
}

variable "region" {
  description = "GCP region for the Redis instance"
  type        = string
  default     = "us-central1"
}

variable "tier" {
  description = "Service tier: BASIC (no replication) or STANDARD_HA (cross-zone replication)"
  type        = string
  default     = "BASIC"

  validation {
    condition     = contains(["BASIC", "STANDARD_HA"], var.tier)
    error_message = "Tier must be either BASIC or STANDARD_HA."
  }
}

variable "memory_size_gb" {
  description = "Redis memory size in GiB"
  type        = number
  default     = 1

  validation {
    condition     = var.memory_size_gb >= 1 && var.memory_size_gb <= 300
    error_message = "Memory size must be between 1 and 300 GiB."
  }
}

variable "redis_version" {
  description = "Redis engine version (e.g., REDIS_7_0, REDIS_7_2)"
  type        = string
  default     = "REDIS_7_2"

  validation {
    condition     = can(regex("^REDIS_[0-9]+_[0-9]+$", var.redis_version))
    error_message = "Redis version must match the format REDIS_X_Y (e.g., REDIS_7_2)."
  }
}

variable "network_id" {
  description = "Self-link or ID of the VPC network to place the Redis instance in"
  type        = string
}

variable "auth_enabled" {
  description = "Enable AUTH for Redis instance (requires a password to connect)"
  type        = bool
  default     = true
}

variable "transit_encryption_mode" {
  description = "Transit encryption mode: DISABLED or SERVER_AUTHENTICATION"
  type        = string
  default     = "SERVER_AUTHENTICATION"

  validation {
    condition     = contains(["DISABLED", "SERVER_AUTHENTICATION"], var.transit_encryption_mode)
    error_message = "Transit encryption mode must be DISABLED or SERVER_AUTHENTICATION."
  }
}

variable "labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
}
