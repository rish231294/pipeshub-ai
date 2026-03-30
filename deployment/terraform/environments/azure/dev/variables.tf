# -----------------------------------------------------------------------------
# PipesHub AI - Azure Environment Variables
# All variables referenced in main.tf are defined here
# -----------------------------------------------------------------------------

# --- General ---

variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Name of the project, used as prefix for all resources"
  type        = string
  default     = "pipeshub-ai"
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "eastus"
}

# --- Networking ---

variable "vnet_cidr" {
  description = "CIDR block for the Virtual Network"
  type        = string
  default     = "10.0.0.0/16"
}

# --- Kubernetes (AKS) ---

variable "aks_kubernetes_version" {
  description = "Kubernetes version for the AKS cluster"
  type        = string
  default     = "1.30"
}

variable "node_pools" {
  description = "Map of AKS node pool configurations"
  type = map(object({
    vm_size      = string
    min_count    = number
    max_count    = number
    node_count   = number
    os_disk_size = number
    labels       = map(string)
    taints       = list(string)
    priority     = string
  }))
  default = {}
}

# --- MongoDB (Cosmos DB) ---

variable "cosmos_db_offer_type" {
  description = "Cosmos DB offer type"
  type        = string
  default     = "Standard"
}

variable "cosmos_db_throughput" {
  description = "Cosmos DB provisioned throughput (RU/s)"
  type        = number
  default     = 400
}

# --- Redis (Azure Cache for Redis) ---

variable "redis_sku_name" {
  description = "SKU name for Azure Cache for Redis"
  type        = string
  default     = "Basic"
}

variable "redis_family" {
  description = "SKU family for Azure Cache for Redis"
  type        = string
  default     = "C"
}

variable "redis_capacity" {
  description = "Size of the Redis cache"
  type        = number
  default     = 0
}

# --- Kafka (Event Hubs) ---

variable "eventhub_sku" {
  description = "SKU for Azure Event Hubs namespace"
  type        = string
  default     = "Basic"
}

variable "eventhub_capacity" {
  description = "Throughput units for Event Hubs"
  type        = number
  default     = 1
}

# --- DNS ---

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
  default     = "dev.pipeshub.example.com"
}

variable "create_dns_zone" {
  description = "Whether to create a new Azure DNS zone"
  type        = bool
  default     = true
}

# --- Application ---

variable "app_namespace" {
  description = "Kubernetes namespace for the application"
  type        = string
  default     = "pipeshub"
}

variable "kv_store_type" {
  description = "Key-value store type (etcd)"
  type        = string
  default     = "etcd"
}

variable "data_store" {
  description = "Graph/document data store type (arangodb)"
  type        = string
  default     = "arangodb"
}

variable "image_tag" {
  description = "Docker image tag to deploy"
  type        = string
  default     = "latest"
}

variable "image_repository" {
  description = "Docker image repository"
  type        = string
  default     = "pipeshubai/pipeshub-ai"
}

variable "app_replica_count" {
  description = "Number of application replicas"
  type        = number
  default     = 1
}

variable "app_resources" {
  description = "Resource requests and limits for the application"
  type = object({
    cpu_limit      = string
    cpu_request    = string
    memory_limit   = string
    memory_request = string
  })
  default = {
    cpu_limit      = "4"
    cpu_request    = "2"
    memory_limit   = "4Gi"
    memory_request = "2Gi"
  }
}

variable "cors_allowed_origins" {
  description = "List of allowed CORS origins"
  type        = list(string)
  default     = ["*"]
}

variable "connector_public_backend" {
  description = "Public URL for the connector backend"
  type        = string
  default     = ""
}

variable "log_level" {
  description = "Application log level (debug, info, warn, error)"
  type        = string
  default     = "debug"
}

# --- ArangoDB ---

variable "arangodb_storage_size" {
  description = "Storage size for ArangoDB persistent volume"
  type        = string
  default     = "10Gi"
}

variable "arangodb_cpu_request" {
  description = "CPU request for ArangoDB"
  type        = string
  default     = "500m"
}

variable "arangodb_cpu_limit" {
  description = "CPU limit for ArangoDB"
  type        = string
  default     = "1000m"
}

variable "arangodb_memory_request" {
  description = "Memory request for ArangoDB"
  type        = string
  default     = "512Mi"
}

variable "arangodb_memory_limit" {
  description = "Memory limit for ArangoDB"
  type        = string
  default     = "1Gi"
}

# --- Qdrant ---

variable "qdrant_storage_size" {
  description = "Storage size for Qdrant persistent volume"
  type        = string
  default     = "10Gi"
}

variable "qdrant_cpu_request" {
  description = "CPU request for Qdrant"
  type        = string
  default     = "500m"
}

variable "qdrant_cpu_limit" {
  description = "CPU limit for Qdrant"
  type        = string
  default     = "1000m"
}

variable "qdrant_memory_request" {
  description = "Memory request for Qdrant"
  type        = string
  default     = "1Gi"
}

variable "qdrant_memory_limit" {
  description = "Memory limit for Qdrant"
  type        = string
  default     = "2Gi"
}

# --- etcd ---

variable "etcd_storage_size" {
  description = "Storage size for etcd persistent volume"
  type        = string
  default     = "1Gi"
}

# --- Observability ---

variable "grafana_admin_password" {
  description = "Admin password for Grafana"
  type        = string
  sensitive   = true
  default     = ""
}

variable "alert_slack_webhook_url" {
  description = "Slack webhook URL for alerting"
  type        = string
  sensitive   = true
  default     = ""
}

# --- Secrets ---

variable "secret_key" {
  description = "Application secret key for encryption"
  type        = string
  sensitive   = true
  default     = ""
}
