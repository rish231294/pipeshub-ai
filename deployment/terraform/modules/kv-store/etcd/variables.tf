variable "enabled" {
  description = "Whether to deploy etcd (conditional on KV_STORE_TYPE configuration)"
  type        = bool
  default     = true
}

variable "namespace" {
  description = "Kubernetes namespace for etcd deployment"
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
  description = "Helm release name for etcd"
  type        = string
  default     = "etcd"
}

variable "chart_version" {
  description = "Version of the Bitnami etcd Helm chart to deploy"
  type        = string
  default     = null
}

variable "image_tag" {
  description = "etcd Docker image tag"
  type        = string
  default     = "3.5.17"
}

variable "replica_count" {
  description = "Number of etcd replicas (1 for dev, 3 for production HA with Raft consensus)"
  type        = number
  default     = 1

  validation {
    condition     = contains([1, 3, 5, 7], var.replica_count)
    error_message = "etcd replica count must be an odd number: 1, 3, 5, or 7."
  }
}

variable "storage_class" {
  description = "Kubernetes StorageClass for persistent volumes (empty string uses cluster default)"
  type        = string
  default     = ""
}

variable "storage_size" {
  description = "Size of the persistent volume for etcd data"
  type        = string
  default     = "1Gi"

  validation {
    condition     = can(regex("^[0-9]+[KMGT]i$", var.storage_size))
    error_message = "Storage size must be a valid Kubernetes quantity (e.g., 1Gi, 5Gi)."
  }
}

variable "cpu_request" {
  description = "CPU request for each etcd pod"
  type        = string
  default     = "100m"
}

variable "cpu_limit" {
  description = "CPU limit for each etcd pod"
  type        = string
  default     = "500m"
}

variable "memory_request" {
  description = "Memory request for each etcd pod"
  type        = string
  default     = "128Mi"
}

variable "memory_limit" {
  description = "Memory limit for each etcd pod"
  type        = string
  default     = "512Mi"
}

variable "auth_enabled" {
  description = "Whether to enable etcd RBAC authentication"
  type        = bool
  default     = false
}

variable "auto_compaction_retention" {
  description = "Auto compaction retention period (e.g., '1' for 1 hour in periodic mode)"
  type        = string
  default     = "1"
}

variable "snapshot_count" {
  description = "Number of committed transactions to trigger a snapshot to disk"
  type        = number
  default     = 10000
}

variable "quota_backend_bytes" {
  description = "Maximum database size in bytes (0 means default 2GB)"
  type        = number
  default     = 0
}

variable "labels" {
  description = "Additional labels to apply to all etcd resources"
  type        = map(string)
  default     = {}
}

variable "node_selector" {
  description = "Node selector for etcd pod scheduling"
  type        = map(string)
  default     = {}
}

variable "tolerations" {
  description = "Tolerations for etcd pod scheduling"
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
