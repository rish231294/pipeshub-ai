variable "namespace" {
  description = "Kubernetes namespace for ArangoDB deployment"
  type        = string
  default     = "pipeshub"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.namespace))
    error_message = "Namespace must consist of lowercase alphanumeric characters or hyphens."
  }
}

variable "create_namespace" {
  description = "Whether to create the Kubernetes namespace"
  type        = bool
  default     = false
}

variable "release_name" {
  description = "Helm release name for ArangoDB"
  type        = string
  default     = "arangodb"
}

variable "image_tag" {
  description = "ArangoDB Docker image tag"
  type        = string
  default     = "3.12.4"
}

variable "storage_class" {
  description = "Kubernetes StorageClass for persistent volumes (empty string uses cluster default)"
  type        = string
  default     = ""
}

variable "storage_size" {
  description = "Size of the persistent volume for ArangoDB data"
  type        = string
  default     = "10Gi"

  validation {
    condition     = can(regex("^[0-9]+[KMGT]i$", var.storage_size))
    error_message = "Storage size must be a valid Kubernetes quantity (e.g., 10Gi, 50Gi)."
  }
}

variable "cpu_request" {
  description = "CPU request for ArangoDB pod"
  type        = string
  default     = "500m"
}

variable "cpu_limit" {
  description = "CPU limit for ArangoDB pod"
  type        = string
  default     = "1"
}

variable "memory_request" {
  description = "Memory request for ArangoDB pod"
  type        = string
  default     = "512Mi"
}

variable "memory_limit" {
  description = "Memory limit for ArangoDB pod"
  type        = string
  default     = "1Gi"
}

variable "root_password_secret_name" {
  description = "Name of the Kubernetes Secret containing the ArangoDB root password"
  type        = string
  default     = "arangodb-root-password"
}

variable "create_root_password_secret" {
  description = "Whether to create the root password secret (set to false if using an external secret)"
  type        = bool
  default     = true
}

variable "root_password" {
  description = "ArangoDB root password (used only when create_root_password_secret is true)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "environment" {
  description = "Deployment environment (dev, staging, production)"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be one of: dev, staging, production."
  }
}

variable "labels" {
  description = "Additional labels to apply to all ArangoDB resources"
  type        = map(string)
  default     = {}
}

variable "node_selector" {
  description = "Node selector for ArangoDB pod scheduling"
  type        = map(string)
  default     = {}
}

variable "tolerations" {
  description = "Tolerations for ArangoDB pod scheduling"
  type = list(object({
    key      = string
    operator = string
    value    = optional(string)
    effect   = string
  }))
  default = []
}

variable "helm_timeout" {
  description = "Timeout in seconds for Helm operations"
  type        = number
  default     = 600
}
