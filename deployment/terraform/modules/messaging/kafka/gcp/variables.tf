###############################################################################
# Kafka Module - GCP Variables
# Defines all input variables for Strimzi-based Kafka on GKE
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

variable "namespace" {
  description = "Kubernetes namespace for Kafka deployment"
  type        = string
  default     = "kafka"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.namespace))
    error_message = "Namespace must be lowercase alphanumeric with hyphens, starting with a letter, max 63 characters."
  }
}

variable "broker_count" {
  description = "Number of Kafka broker replicas (1 for dev, 3 for prod)"
  type        = number
  default     = 1

  validation {
    condition     = var.broker_count >= 1 && var.broker_count <= 9
    error_message = "Broker count must be between 1 and 9."
  }
}

variable "storage_size" {
  description = "Persistent volume size per broker (e.g., 10Gi, 100Gi)"
  type        = string
  default     = "10Gi"

  validation {
    condition     = can(regex("^[0-9]+Gi$", var.storage_size))
    error_message = "Storage size must be in the format NUMBERGi (e.g., 10Gi, 100Gi)."
  }
}

variable "storage_class" {
  description = "Kubernetes storage class for Kafka persistent volumes"
  type        = string
  default     = "standard"
}

variable "cpu_request" {
  description = "CPU request per Kafka broker"
  type        = string
  default     = "500m"
}

variable "cpu_limit" {
  description = "CPU limit per Kafka broker"
  type        = string
  default     = "1000m"
}

variable "memory_request" {
  description = "Memory request per Kafka broker"
  type        = string
  default     = "1Gi"
}

variable "memory_limit" {
  description = "Memory limit per Kafka broker"
  type        = string
  default     = "2Gi"
}

variable "topics" {
  description = "List of Kafka topics to create"
  type = list(object({
    name       = string
    partitions = optional(number, 3)
    replicas   = optional(number, 1)
    config     = optional(map(string), {})
  }))
  default = [
    {
      name       = "record-events"
      partitions = 3
      replicas   = 1
    },
    {
      name       = "entity-events"
      partitions = 3
      replicas   = 1
    },
    {
      name       = "sync-events"
      partitions = 3
      replicas   = 1
    },
  ]
}

variable "kafka_version" {
  description = "Kafka version to deploy via Strimzi"
  type        = string
  default     = "3.8.0"
}

variable "labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
}
