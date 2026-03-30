###############################################################################
# MongoDB Module - Azure (Cosmos DB with MongoDB API) Variables
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

variable "account_name" {
  description = "Name of the Cosmos DB account. If not provided, one will be generated"
  type        = string
  default     = ""

  validation {
    condition     = var.account_name == "" || can(regex("^[a-z0-9][a-z0-9-]{1,42}[a-z0-9]$", var.account_name))
    error_message = "Account name must be 3-44 characters, lowercase alphanumeric with hyphens."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region for the primary Cosmos DB instance"
  type        = string
  default     = "eastus"
}

variable "database_subnet_id" {
  description = "ID of the database subnet for the private endpoint"
  type        = string
}

variable "capacity_mode" {
  description = "Capacity mode for the Cosmos DB account: 'Serverless' for dev/test, 'Provisioned' for production"
  type        = string
  default     = "Serverless"

  validation {
    condition     = contains(["Serverless", "Provisioned"], var.capacity_mode)
    error_message = "Capacity mode must be either 'Serverless' or 'Provisioned'."
  }
}

variable "max_throughput" {
  description = "Maximum throughput (RU/s) for autoscale when using provisioned capacity mode"
  type        = number
  default     = 4000

  validation {
    condition     = var.max_throughput >= 1000 && var.max_throughput <= 1000000
    error_message = "Max throughput must be between 1000 and 1000000 RU/s."
  }
}

variable "database_name" {
  description = "Name of the MongoDB database to create"
  type        = string
  default     = "pipeshub"
}

variable "consistency_level" {
  description = "Default consistency level for the Cosmos DB account"
  type        = string
  default     = "Session"

  validation {
    condition     = contains(["Eventual", "ConsistentPrefix", "Session", "BoundedStaleness", "Strong"], var.consistency_level)
    error_message = "Consistency level must be one of: Eventual, ConsistentPrefix, Session, BoundedStaleness, Strong."
  }
}

variable "geo_replication_locations" {
  description = "Additional locations for geo-replication (prod only). Each entry needs location and failover_priority"
  type = list(object({
    location          = string
    failover_priority = number
  }))
  default = []
}

variable "collections" {
  description = "Map of MongoDB collections to create with their shard keys"
  type = map(object({
    shard_key  = string
    throughput = optional(number, null)
  }))
  default = {
    users = {
      shard_key = "orgId"
    }
    organizations = {
      shard_key = "_id"
    }
    sessions = {
      shard_key = "userId"
    }
    knowledge_bases = {
      shard_key = "orgId"
    }
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
