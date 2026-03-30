###############################################################################
# DocumentDB Module - AWS Variables
# Amazon DocumentDB (MongoDB-compatible) cluster configuration
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

variable "cluster_identifier" {
  description = "Identifier for the DocumentDB cluster"
  type        = string
  default     = ""
}

variable "instance_class" {
  description = "Instance class for DocumentDB instances"
  type        = string
  default     = "db.r6g.large"

  validation {
    condition     = can(regex("^db\\.", var.instance_class))
    error_message = "Instance class must start with 'db.' prefix."
  }
}

variable "instance_count" {
  description = "Number of DocumentDB instances in the cluster"
  type        = number
  default     = 1

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 16
    error_message = "Instance count must be between 1 and 16."
  }
}

variable "vpc_id" {
  description = "ID of the VPC where DocumentDB will be deployed"
  type        = string
}

variable "database_subnet_ids" {
  description = "List of database subnet IDs for the DocumentDB subnet group"
  type        = list(string)

  validation {
    condition     = length(var.database_subnet_ids) >= 2
    error_message = "At least 2 database subnets must be provided."
  }
}

variable "allowed_security_group_ids" {
  description = "List of security group IDs allowed to access DocumentDB"
  type        = list(string)
}

variable "engine_version" {
  description = "DocumentDB engine version"
  type        = string
  default     = "5.0.0"
}

variable "backup_retention_period" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_period >= 1 && var.backup_retention_period <= 35
    error_message = "Backup retention period must be between 1 and 35 days."
  }
}

variable "master_username" {
  description = "Master username for the DocumentDB cluster"
  type        = string
  default     = "pipeshubadmin"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{2,62}$", var.master_username))
    error_message = "Master username must start with a letter, contain only alphanumeric characters and underscores, and be 3-63 characters."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
