###############################################################################
# DNS Module - Azure (DNS Zone + cert-manager + NGINX Ingress) Variables
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

variable "domain_name" {
  description = "Domain name for the DNS zone (e.g., pipeshub.example.com)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]+[a-z0-9]$", var.domain_name))
    error_message = "Domain name must be a valid DNS domain."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "create_zone" {
  description = "Whether to create a new DNS zone or use an existing one"
  type        = bool
  default     = true
}

variable "cert_manager_email" {
  description = "Email address for Let's Encrypt certificate notifications"
  type        = string
  default     = ""
}

variable "ingress_namespace" {
  description = "Kubernetes namespace for the NGINX Ingress Controller"
  type        = string
  default     = "ingress-nginx"
}

variable "cert_manager_namespace" {
  description = "Kubernetes namespace for cert-manager"
  type        = string
  default     = "cert-manager"
}

variable "ingress_replica_count" {
  description = "Number of NGINX Ingress Controller replicas"
  type        = number
  default     = 2
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
