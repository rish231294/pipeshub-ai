###############################################################################
# DNS Module - GCP Variables
# Defines all input variables for Cloud DNS, SSL certificates, and ingress
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

variable "domain_name" {
  description = "Fully qualified domain name for the application (e.g., app.example.com)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]+[a-z0-9]$", var.domain_name))
    error_message = "Domain name must be a valid DNS name."
  }
}

variable "managed_zone_name" {
  description = "Name for the Cloud DNS managed zone"
  type        = string
  default     = ""

  validation {
    condition     = var.managed_zone_name == "" || can(regex("^[a-z][a-z0-9-]{0,62}$", var.managed_zone_name))
    error_message = "Managed zone name must be lowercase alphanumeric with hyphens, starting with a letter."
  }
}

variable "create_zone" {
  description = "Whether to create a new Cloud DNS zone or use an existing one"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
}
