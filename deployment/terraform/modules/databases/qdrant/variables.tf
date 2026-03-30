variable "namespace" {
  description = "Kubernetes namespace for Qdrant deployment"
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
  description = "Helm release name for Qdrant"
  type        = string
  default     = "qdrant"
}

variable "chart_version" {
  description = "Version of the Qdrant Helm chart to deploy"
  type        = string
  default     = null
}

variable "image_tag" {
  description = "Qdrant Docker image tag"
  type        = string
  default     = "v1.15"
}

variable "replica_count" {
  description = "Number of Qdrant replicas (1 for dev, 3+ for production HA)"
  type        = number
  default     = 1

  validation {
    condition     = var.replica_count >= 1
    error_message = "Replica count must be at least 1."
  }
}

variable "storage_class" {
  description = "Kubernetes StorageClass for persistent volumes (empty string uses cluster default)"
  type        = string
  default     = ""
}

variable "storage_size" {
  description = "Size of the persistent volume for Qdrant vector storage"
  type        = string
  default     = "10Gi"

  validation {
    condition     = can(regex("^[0-9]+[KMGT]i$", var.storage_size))
    error_message = "Storage size must be a valid Kubernetes quantity (e.g., 10Gi, 100Gi)."
  }
}

variable "cpu_request" {
  description = "CPU request for each Qdrant pod"
  type        = string
  default     = "500m"
}

variable "cpu_limit" {
  description = "CPU limit for each Qdrant pod"
  type        = string
  default     = "1"
}

variable "memory_request" {
  description = "Memory request for each Qdrant pod"
  type        = string
  default     = "512Mi"
}

variable "memory_limit" {
  description = "Memory limit for each Qdrant pod"
  type        = string
  default     = "1Gi"
}

variable "api_key_secret_name" {
  description = "Name of the Kubernetes Secret containing the Qdrant API key"
  type        = string
  default     = "qdrant-api-key"
}

variable "create_api_key_secret" {
  description = "Whether to create the API key secret (set to false if using an external secret)"
  type        = bool
  default     = true
}

variable "api_key" {
  description = "Qdrant API key for authentication (used only when create_api_key_secret is true)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "node_selector" {
  description = "Node selector labels for Qdrant pod scheduling (e.g., for data node groups)"
  type        = map(string)
  default     = {}
}

variable "tolerations" {
  description = "Tolerations for Qdrant pod scheduling"
  type = list(object({
    key      = string
    operator = string
    value    = optional(string)
    effect   = string
  }))
  default = []
}

# Performance tuning variables
variable "optimizer_segment_number" {
  description = "Number of segments for Qdrant storage optimizer (higher = more parallelism)"
  type        = number
  default     = 8

  validation {
    condition     = var.optimizer_segment_number >= 1 && var.optimizer_segment_number <= 64
    error_message = "Segment number must be between 1 and 64."
  }
}

variable "optimizer_memmap_threshold" {
  description = "Threshold (in KB) above which vectors are stored in memory-mapped files"
  type        = number
  default     = 50000
}

variable "wal_capacity_mb" {
  description = "Write-ahead log capacity in megabytes"
  type        = number
  default     = 256

  validation {
    condition     = var.wal_capacity_mb >= 32
    error_message = "WAL capacity must be at least 32 MB."
  }
}

variable "labels" {
  description = "Additional labels to apply to all Qdrant resources"
  type        = map(string)
  default     = {}
}

variable "helm_timeout" {
  description = "Timeout in seconds for Helm operations"
  type        = number
  default     = 600
}
