###############################################################################
# Redis (ElastiCache) Module - AWS Variables
# Defines all input variables for ElastiCache Redis replication group
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
}

variable "replication_group_id" {
  description = "ID for the ElastiCache Redis replication group"
  type        = string
  default     = ""

  validation {
    condition     = var.replication_group_id == "" || can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", var.replication_group_id))
    error_message = "Replication group ID must be lowercase alphanumeric with hyphens, 1-40 characters, starting with a letter."
  }
}

variable "node_type" {
  description = "ElastiCache node type for Redis instances"
  type        = string
  default     = "cache.r6g.large"

  validation {
    condition     = can(regex("^cache\\.", var.node_type))
    error_message = "Node type must start with 'cache.' prefix."
  }
}

variable "num_cache_clusters" {
  description = "Number of cache clusters (nodes) in the replication group. 1 for dev (no replicas), 2+ for prod"
  type        = number
  default     = 1

  validation {
    condition     = var.num_cache_clusters >= 1 && var.num_cache_clusters <= 6
    error_message = "Number of cache clusters must be between 1 and 6."
  }
}

variable "vpc_id" {
  description = "ID of the VPC where ElastiCache will be deployed"
  type        = string
}

variable "database_subnet_ids" {
  description = "List of database subnet IDs for the ElastiCache subnet group"
  type        = list(string)

  validation {
    condition     = length(var.database_subnet_ids) >= 2
    error_message = "At least 2 database subnets must be provided."
  }
}

variable "allowed_security_group_ids" {
  description = "List of security group IDs allowed to access Redis"
  type        = list(string)
}

variable "engine_version" {
  description = "Redis engine version"
  type        = string
  default     = "7.1"
}

variable "at_rest_encryption" {
  description = "Enable encryption at rest for ElastiCache"
  type        = bool
  default     = true
}

variable "transit_encryption" {
  description = "Enable encryption in transit for ElastiCache"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
