###############################################################################
# Redis Module - Azure (Azure Cache for Redis) Variables
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

variable "cache_name" {
  description = "Name of the Azure Cache for Redis instance. If not provided, one will be generated"
  type        = string
  default     = ""
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

variable "sku_name" {
  description = "SKU name for the Redis cache: Basic (dev), Standard (staging), Premium (prod)"
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku_name)
    error_message = "SKU name must be one of: Basic, Standard, Premium."
  }
}

variable "family" {
  description = "SKU family: C (Basic/Standard) or P (Premium)"
  type        = string
  default     = "C"

  validation {
    condition     = contains(["C", "P"], var.family)
    error_message = "Family must be either 'C' (Basic/Standard) or 'P' (Premium)."
  }
}

variable "capacity" {
  description = "Size of the Redis cache: 0-6 for C family, 1-5 for P family"
  type        = number
  default     = 0

  validation {
    condition     = var.capacity >= 0 && var.capacity <= 6
    error_message = "Capacity must be between 0 and 6."
  }
}

variable "enable_non_ssl_port" {
  description = "Enable the non-SSL port (6379). Should be false for production"
  type        = bool
  default     = false
}

variable "minimum_tls_version" {
  description = "Minimum TLS version for connections"
  type        = string
  default     = "1.2"

  validation {
    condition     = contains(["1.0", "1.1", "1.2"], var.minimum_tls_version)
    error_message = "Minimum TLS version must be one of: 1.0, 1.1, 1.2."
  }
}

variable "maxmemory_policy" {
  description = "Redis maxmemory eviction policy"
  type        = string
  default     = "allkeys-lru"

  validation {
    condition = contains([
      "volatile-lru", "allkeys-lru", "volatile-lfu", "allkeys-lfu",
      "volatile-random", "allkeys-random", "volatile-ttl", "noeviction"
    ], var.maxmemory_policy)
    error_message = "Invalid maxmemory policy. Must be one of: volatile-lru, allkeys-lru, volatile-lfu, allkeys-lfu, volatile-random, allkeys-random, volatile-ttl, noeviction."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
