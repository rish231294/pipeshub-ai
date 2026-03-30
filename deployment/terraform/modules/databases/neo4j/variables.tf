variable "enabled" {
  description = "Whether to deploy Neo4j (set to true when DATA_STORE=neo4j)"
  type        = bool
  default     = false
}

variable "namespace" {
  description = "Kubernetes namespace for Neo4j deployment"
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
  description = "Helm release name for Neo4j"
  type        = string
  default     = "neo4j"
}

variable "chart_version" {
  description = "Version of the Neo4j Helm chart to deploy"
  type        = string
  default     = "5.26.0"
}

variable "image_tag" {
  description = "Neo4j Docker image tag"
  type        = string
  default     = "5.26.0"
}

variable "storage_class" {
  description = "Kubernetes StorageClass for persistent volumes (empty string uses cluster default)"
  type        = string
  default     = ""
}

variable "storage_size" {
  description = "Size of the persistent volume for Neo4j data"
  type        = string
  default     = "10Gi"

  validation {
    condition     = can(regex("^[0-9]+[KMGT]i$", var.storage_size))
    error_message = "Storage size must be a valid Kubernetes quantity (e.g., 10Gi, 50Gi)."
  }
}

variable "cpu_request" {
  description = "CPU request for Neo4j pod"
  type        = string
  default     = "1000m"
}

variable "cpu_limit" {
  description = "CPU limit for Neo4j pod"
  type        = string
  default     = "2000m"
}

variable "memory_request" {
  description = "Memory request for Neo4j pod"
  type        = string
  default     = "1Gi"
}

variable "memory_limit" {
  description = "Memory limit for Neo4j pod"
  type        = string
  default     = "2Gi"
}

variable "auth_secret_name" {
  description = "Name of the Kubernetes Secret containing Neo4j authentication credentials"
  type        = string
  default     = "neo4j-auth"
}

variable "create_auth_secret" {
  description = "Whether to create the auth secret (set to false if using an external secret)"
  type        = bool
  default     = true
}

variable "neo4j_password" {
  description = "Neo4j password (used only when create_auth_secret is true)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "heap_initial_size" {
  description = "JVM initial heap size for Neo4j"
  type        = string
  default     = "256m"

  validation {
    condition     = can(regex("^[0-9]+[kmgKMG]$", var.heap_initial_size))
    error_message = "Heap size must be a valid JVM memory value (e.g., 256m, 1g, 2G)."
  }
}

variable "heap_max_size" {
  description = "JVM maximum heap size for Neo4j"
  type        = string
  default     = "512m"

  validation {
    condition     = can(regex("^[0-9]+[kmgKMG]$", var.heap_max_size))
    error_message = "Heap size must be a valid JVM memory value (e.g., 512m, 2g, 4G)."
  }
}

variable "pagecache_size" {
  description = "Neo4j page cache size for caching graph data on disk"
  type        = string
  default     = "256m"

  validation {
    condition     = can(regex("^[0-9]+[kmgKMG]$", var.pagecache_size))
    error_message = "Page cache size must be a valid memory value (e.g., 256m, 1g)."
  }
}

variable "labels" {
  description = "Additional labels to apply to all Neo4j resources"
  type        = map(string)
  default     = {}
}

variable "node_selector" {
  description = "Node selector for Neo4j pod scheduling"
  type        = map(string)
  default     = {}
}

variable "tolerations" {
  description = "Tolerations for Neo4j pod scheduling"
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
