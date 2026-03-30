variable "namespace" {
  description = "Kubernetes namespace for the PipesHub AI application"
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
  description = "Helm release name for PipesHub AI"
  type        = string
  default     = "pipeshub-ai"
}

variable "chart_path" {
  description = "Path to the PipesHub AI Helm chart directory"
  type        = string
  default     = "../../helm/pipeshub-ai"
}

variable "image_tag" {
  description = "Docker image tag for PipesHub AI"
  type        = string
  default     = "latest"
}

variable "image_repository" {
  description = "Docker image repository for PipesHub AI"
  type        = string
  default     = "pipeshubai/pipeshub-ai"
}

variable "image_pull_policy" {
  description = "Image pull policy for the PipesHub AI container"
  type        = string
  default     = "Always"

  validation {
    condition     = contains(["Always", "IfNotPresent", "Never"], var.image_pull_policy)
    error_message = "Image pull policy must be one of: Always, IfNotPresent, Never."
  }
}

variable "replica_count" {
  description = "Number of PipesHub AI pod replicas"
  type        = number
  default     = 1

  validation {
    condition     = var.replica_count >= 1
    error_message = "Replica count must be at least 1."
  }
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

variable "storage_class" {
  description = "Kubernetes StorageClass for application persistent storage"
  type        = string
  default     = ""
}

variable "storage_size" {
  description = "Size of the persistent volume for application data"
  type        = string
  default     = "10Gi"

  validation {
    condition     = can(regex("^[0-9]+[KMGT]i$", var.storage_size))
    error_message = "Storage size must be a valid Kubernetes quantity (e.g., 10Gi)."
  }
}

# ---------------------------------------------------------------------------
# Managed Service Endpoints
# When a managed service endpoint is provided (non-empty), the corresponding
# in-cluster deployment is disabled and the managed endpoint is used instead.
# ---------------------------------------------------------------------------

variable "managed_service_endpoints" {
  description = "Endpoints for managed cloud services. Non-empty values disable in-cluster deployment of that component."
  type = object({
    mongo_uri            = optional(string, "")
    redis_host           = optional(string, "")
    redis_port           = optional(number, 6379)
    redis_password       = optional(string, "")
    kafka_brokers        = optional(string, "")
    kafka_ssl            = optional(bool, false)
    kafka_sasl_mechanism = optional(string, "")
    kafka_username       = optional(string, "")
    qdrant_host          = optional(string, "")
    qdrant_port          = optional(number, 6333)
    qdrant_grpc_port     = optional(number, 6334)
    qdrant_api_key       = optional(string, "")
    arango_url           = optional(string, "")
    arango_password      = optional(string, "")
    etcd_url             = optional(string, "")
    etcd_host            = optional(string, "")
    neo4j_uri            = optional(string, "")
    neo4j_username       = optional(string, "neo4j")
    neo4j_password       = optional(string, "")
    neo4j_database       = optional(string, "neo4j")
  })
  default   = {}
  sensitive = true
}

# ---------------------------------------------------------------------------
# Application Configuration
# ---------------------------------------------------------------------------

variable "app_config" {
  description = "PipesHub AI application-level configuration"
  type = object({
    secret_key               = string
    frontend_public_url      = optional(string, "")
    connector_public_backend = optional(string, "")
    log_level                = optional(string, "info")
    node_env                 = optional(string, "production")
    allowed_origins          = optional(string, "*")
    kv_store_type            = optional(string, "")
    data_store               = optional(string, "")
  })
  sensitive = true

  validation {
    condition     = contains(["error", "warn", "info", "debug", "trace"], var.app_config.log_level)
    error_message = "Log level must be one of: error, warn, info, debug, trace."
  }

  validation {
    condition     = contains(["development", "production", "test"], var.app_config.node_env)
    error_message = "Node environment must be one of: development, production, test."
  }

  validation {
    condition     = var.app_config.data_store == "" || contains(["arangodb", "arango", "neo4j"], var.app_config.data_store)
    error_message = "Data store must be empty (defaults to arangodb) or one of: arangodb, arango, neo4j."
  }
}

# ---------------------------------------------------------------------------
# Resource Limits
# ---------------------------------------------------------------------------

variable "resources" {
  description = "CPU and memory resource requests and limits for the PipesHub AI pod"
  type = object({
    cpu_request    = optional(string, "4")
    cpu_limit      = optional(string, "8")
    memory_request = optional(string, "4Gi")
    memory_limit   = optional(string, "8Gi")
  })
  default = {}
}

# ---------------------------------------------------------------------------
# Ingress Configuration
# ---------------------------------------------------------------------------

variable "ingress_config" {
  description = "Ingress configuration for external access to PipesHub AI"
  type = object({
    enabled         = optional(bool, false)
    class_name      = optional(string, "")
    hostname        = optional(string, "")
    tls_secret_name = optional(string, "")
    annotations     = optional(map(string), {})
  })
  default = {}
}

# ---------------------------------------------------------------------------
# Helm values override file
# ---------------------------------------------------------------------------

variable "values_file" {
  description = "Path to an environment-specific Helm values override file (e.g., dev.yaml, production.yaml)"
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Common
# ---------------------------------------------------------------------------

variable "labels" {
  description = "Additional labels to apply to all application resources"
  type        = map(string)
  default     = {}
}

variable "helm_timeout" {
  description = "Timeout in seconds for Helm operations"
  type        = number
  default     = 900
}
