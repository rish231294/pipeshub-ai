# -----------------------------------------------------------------------------
# PipesHub AI - GCP Environment Variables
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

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for all resources"
  type        = string
  default     = "us-central1"
}

# --- Networking ---

variable "vpc_cidr" {
  description = "CIDR block for the VPC subnet"
  type        = string
  default     = "10.0.0.0/16"
}

# --- Kubernetes (GKE) ---

variable "gke_kubernetes_version" {
  description = "Kubernetes version for the GKE cluster"
  type        = string
  default     = "1.30"
}

variable "node_pools" {
  description = "Map of GKE node pool configurations"
  type = map(object({
    machine_type   = string
    min_count      = number
    max_count      = number
    initial_count  = number
    disk_size_gb   = number
    disk_type      = string
    labels         = map(string)
    taints         = list(object({ key = string, value = string, effect = string }))
    preemptible    = bool
    spot           = bool
  }))
  default = {}
}

# --- MongoDB ---

variable "mongodb_instance_tier" {
  description = "Instance tier for MongoDB (Compute Engine or Atlas)"
  type        = string
  default     = "db-f1-micro"
}

variable "mongodb_disk_size_gb" {
  description = "Disk size in GB for MongoDB"
  type        = number
  default     = 20
}

# --- Redis (Memorystore) ---

variable "redis_memory_size_gb" {
  description = "Memory size in GB for Cloud Memorystore Redis"
  type        = number
  default     = 1
}

variable "redis_tier" {
  description = "Service tier for Cloud Memorystore Redis"
  type        = string
  default     = "BASIC"
}

# --- Kafka ---

variable "kafka_broker_count" {
  description = "Number of Kafka broker nodes"
  type        = number
  default     = 2
}

variable "kafka_broker_machine_type" {
  description = "Machine type for Kafka broker nodes"
  type        = string
  default     = "e2-standard-2"
}

variable "kafka_disk_size_gb" {
  description = "Disk size in GB per Kafka broker"
  type        = number
  default     = 100
}

# --- DNS ---

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
  default     = "dev.pipeshub.example.com"
}

variable "create_dns_zone" {
  description = "Whether to create a new Cloud DNS zone"
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
