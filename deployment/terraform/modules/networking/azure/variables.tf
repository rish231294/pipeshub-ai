###############################################################################
# Networking Module - Azure Variables
# Defines all input variables for VNet, subnets, NSGs, and NAT Gateway
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

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Name of the resource group. If not provided, one will be generated from project_name and environment"
  type        = string
  default     = ""
}

variable "vnet_address_space" {
  description = "Address space for the Virtual Network"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vnet_address_space, 0))
    error_message = "VNet address space must be a valid IPv4 CIDR block."
  }
}

variable "aks_subnet_cidr" {
  description = "CIDR block for the AKS subnet"
  type        = string
  default     = "10.0.0.0/18"

  validation {
    condition     = can(cidrhost(var.aks_subnet_cidr, 0))
    error_message = "AKS subnet CIDR must be a valid IPv4 CIDR block."
  }
}

variable "database_subnet_cidr" {
  description = "CIDR block for the database subnet"
  type        = string
  default     = "10.0.64.0/20"

  validation {
    condition     = can(cidrhost(var.database_subnet_cidr, 0))
    error_message = "Database subnet CIDR must be a valid IPv4 CIDR block."
  }
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.80.0/22"

  validation {
    condition     = can(cidrhost(var.public_subnet_cidr, 0))
    error_message = "Public subnet CIDR must be a valid IPv4 CIDR block."
  }
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for AKS subnet outbound connectivity"
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Enable VNet Flow Logs (requires storage_account_id to be set)"
  type        = bool
  default     = false
}

variable "flow_log_storage_account_id" {
  description = "Storage account ID for VNet Flow Logs. Required when enable_flow_logs is true"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
