# -----------------------------------------------------------------------------
# PipesHub AI - AWS Environment Variables
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

variable "region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

# --- Networking ---

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones to use"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

# --- Kubernetes (EKS) ---

variable "eks_cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.30"
}

variable "node_groups" {
  description = "Map of EKS managed node group configurations"
  type = map(object({
    instance_types = list(string)
    min_size       = number
    max_size       = number
    desired_size   = number
    capacity_type  = string
    disk_size      = number
    labels         = map(string)
    taints         = list(any)
  }))
  default = {}
}

# --- MongoDB (DocumentDB) ---

variable "mongodb_instance_class" {
  description = "Instance class for DocumentDB instances"
  type        = string
  default     = "db.t3.medium"
}

variable "mongodb_instance_count" {
  description = "Number of DocumentDB instances in the cluster"
  type        = number
  default     = 1
}

# --- Redis (ElastiCache) ---

variable "redis_node_type" {
  description = "Node type for ElastiCache Redis"
  type        = string
  default     = "cache.t3.micro"
}

variable "redis_num_cache_clusters" {
  description = "Number of cache clusters (nodes) for Redis replication group"
  type        = number
  default     = 1
}

# --- Kafka (MSK) ---

variable "kafka_broker_instance_type" {
  description = "Instance type for MSK broker nodes"
  type        = string
  default     = "kafka.t3.small"
}

variable "kafka_broker_count" {
  description = "Number of broker nodes in the MSK cluster"
  type        = number
  default     = 2
}

# --- DNS ---

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
  default     = "dev.pipeshub.example.com"
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID (required if create_dns_zone is false)"
  type        = string
  default     = ""
}

variable "create_dns_zone" {
  description = "Whether to create a new Route53 hosted zone"
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
  description = "List of allowed CORS origins for the S3 bucket"
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
