###############################################################################
# Kafka (MSK) Module - AWS Variables
# Defines all input variables for Amazon MSK cluster
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

variable "cluster_name" {
  description = "Name of the MSK cluster"
  type        = string
  default     = ""
}

variable "kafka_version" {
  description = "Apache Kafka version for the MSK cluster"
  type        = string
  default     = "3.6.0"
}

variable "broker_instance_type" {
  description = "Instance type for MSK broker nodes"
  type        = string
  default     = "kafka.m5.large"

  validation {
    condition     = can(regex("^kafka\\.", var.broker_instance_type))
    error_message = "Broker instance type must start with 'kafka.' prefix."
  }
}

variable "broker_count" {
  description = "Number of broker nodes in the MSK cluster (must be a multiple of the number of AZs)"
  type        = number
  default     = 3

  validation {
    condition     = var.broker_count >= 1 && var.broker_count <= 15
    error_message = "Broker count must be between 1 and 15."
  }
}

variable "vpc_id" {
  description = "ID of the VPC where MSK will be deployed"
  type        = string
}

variable "database_subnet_ids" {
  description = "List of database subnet IDs for MSK broker placement"
  type        = list(string)

  validation {
    condition     = length(var.database_subnet_ids) >= 2
    error_message = "At least 2 database subnets must be provided."
  }
}

variable "allowed_security_group_ids" {
  description = "List of security group IDs allowed to access MSK"
  type        = list(string)
}

variable "ebs_volume_size" {
  description = "Size of the EBS volume (in GiB) attached to each broker node"
  type        = number
  default     = 100

  validation {
    condition     = var.ebs_volume_size >= 1 && var.ebs_volume_size <= 16384
    error_message = "EBS volume size must be between 1 and 16384 GiB."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
