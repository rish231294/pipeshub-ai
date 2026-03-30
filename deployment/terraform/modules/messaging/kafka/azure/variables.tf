###############################################################################
# Kafka Module - Azure (Event Hubs with Kafka Protocol) Variables
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

variable "namespace_name" {
  description = "Name of the Event Hubs namespace. If not provided, one will be generated"
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

variable "sku" {
  description = "SKU tier for the Event Hubs namespace: Standard (dev/staging) or Premium (prod)"
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Premium"], var.sku)
    error_message = "SKU must be either 'Standard' or 'Premium'. Basic tier does not support Kafka protocol."
  }
}

variable "capacity" {
  description = "Throughput units for Standard tier (1-20) or processing units for Premium tier (1-10)"
  type        = number
  default     = 1

  validation {
    condition     = var.capacity >= 1 && var.capacity <= 20
    error_message = "Capacity must be between 1 and 20."
  }
}

variable "topics" {
  description = "List of Kafka topic configurations (mapped to Event Hubs)"
  type = list(object({
    name            = string
    partition_count = number
    retention_days  = number
  }))
  default = [
    {
      name            = "record-events"
      partition_count = 4
      retention_days  = 7
    },
    {
      name            = "entity-events"
      partition_count = 4
      retention_days  = 7
    },
    {
      name            = "sync-events"
      partition_count = 4
      retention_days  = 7
    }
  ]

  validation {
    condition     = length(var.topics) > 0
    error_message = "At least one topic must be configured."
  }
}

variable "consumer_groups" {
  description = "Map of consumer group names to the topic they belong to"
  type = map(object({
    topic_name = string
    user_metadata = optional(string, "")
  }))
  default = {
    "indexing-consumer" = {
      topic_name    = "record-events"
      user_metadata = "Indexing service consumer group"
    }
    "connector-consumer" = {
      topic_name    = "entity-events"
      user_metadata = "Connector service consumer group"
    }
    "sync-consumer" = {
      topic_name    = "sync-events"
      user_metadata = "Sync service consumer group"
    }
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
