# -----------------------------------------------------------------------------
# PipesHub AI - GCP Production Environment
# Main composition file that wires all modules together
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Configure Kubernetes provider after GKE is created
provider "kubernetes" {
  host                   = "https://${module.kubernetes.cluster_endpoint}"
  cluster_ca_certificate = base64decode(module.kubernetes.cluster_certificate_authority)
  token                  = data.google_client_config.default.access_token
}

# Configure Helm provider after GKE is created
provider "helm" {
  kubernetes {
    host                   = "https://${module.kubernetes.cluster_endpoint}"
    cluster_ca_certificate = base64decode(module.kubernetes.cluster_certificate_authority)
    token                  = data.google_client_config.default.access_token
  }
}

data "google_client_config" "default" {}

locals {
  common_labels = {
    environment = var.environment
    project     = var.project_name
    managed-by  = "terraform"
  }
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------

module "networking" {
  source = "../../../modules/networking/gcp"

  environment  = var.environment
  project_name = var.project_name
  project_id   = var.project_id
  region       = var.region
  vpc_cidr     = var.vpc_cidr
  labels       = local.common_labels
}

# -----------------------------------------------------------------------------
# Kubernetes (GKE)
# -----------------------------------------------------------------------------

module "kubernetes" {
  source = "../../../modules/kubernetes/gcp"

  environment        = var.environment
  project_name       = var.project_name
  project_id         = var.project_id
  region             = var.region
  cluster_name       = "${var.project_name}-${var.environment}"
  kubernetes_version = var.gke_kubernetes_version
  network_id         = module.networking.network_id
  subnet_id          = module.networking.subnet_id
  node_pools         = var.node_pools
  labels             = local.common_labels
}

# -----------------------------------------------------------------------------
# Managed MongoDB (MongoDB Atlas)
# -----------------------------------------------------------------------------

module "mongodb" {
  source = "../../../modules/databases/mongodb/gcp"

  environment    = var.environment
  project_name   = var.project_name
  project_id     = var.project_id
  region         = var.region
  instance_tier  = var.mongodb_instance_tier
  disk_size_gb   = var.mongodb_disk_size_gb
  network_id     = module.networking.network_id
  labels         = local.common_labels
}

# -----------------------------------------------------------------------------
# Managed Redis (Cloud Memorystore)
# -----------------------------------------------------------------------------

module "redis" {
  source = "../../../modules/databases/redis/gcp"

  environment    = var.environment
  project_name   = var.project_name
  project_id     = var.project_id
  region         = var.region
  memory_size_gb = var.redis_memory_size_gb
  tier           = var.redis_tier
  network_id     = module.networking.network_id
  labels         = local.common_labels
}

# -----------------------------------------------------------------------------
# Managed Kafka (Strimzi on GKE)
# -----------------------------------------------------------------------------

module "kafka" {
  source = "../../../modules/messaging/kafka/gcp"

  environment         = var.environment
  project_name        = var.project_name
  project_id          = var.project_id
  region              = var.region
  broker_count        = var.kafka_broker_count
  broker_machine_type = var.kafka_broker_machine_type
  disk_size_gb        = var.kafka_disk_size_gb
  network_id          = module.networking.network_id
  subnet_id           = module.networking.subnet_id
  labels              = local.common_labels
}

# -----------------------------------------------------------------------------
# Secrets Management
# -----------------------------------------------------------------------------

module "secrets" {
  source = "../../../modules/secrets/gcp"

  environment         = var.environment
  project_name        = var.project_name
  project_id          = var.project_id
  gke_service_account = module.kubernetes.service_account_email
  labels              = local.common_labels
}

# -----------------------------------------------------------------------------
# DNS & TLS
# -----------------------------------------------------------------------------

module "dns" {
  source = "../../../modules/dns/gcp"

  environment  = var.environment
  project_name = var.project_name
  project_id   = var.project_id
  domain_name  = var.domain_name
  create_zone  = var.create_dns_zone
  labels       = local.common_labels
}

# -----------------------------------------------------------------------------
# Object Storage (GCS)
# -----------------------------------------------------------------------------

module "storage" {
  source = "../../../modules/storage/gcp"

  environment          = var.environment
  project_name         = var.project_name
  project_id           = var.project_id
  region               = var.region
  bucket_name          = "${var.project_name}-${var.environment}-documents"
  cors_allowed_origins = var.cors_allowed_origins
  gke_service_account  = module.kubernetes.service_account_email
  labels               = local.common_labels
}

# -----------------------------------------------------------------------------
# Self-hosted: ArangoDB on K8s
# -----------------------------------------------------------------------------

module "arangodb" {
  source = "../../../modules/databases/arangodb"

  namespace                 = var.app_namespace
  storage_class             = "premium-rwo"
  storage_size              = var.arangodb_storage_size
  cpu_request               = var.arangodb_cpu_request
  cpu_limit                 = var.arangodb_cpu_limit
  memory_request            = var.arangodb_memory_request
  memory_limit              = var.arangodb_memory_limit
  root_password_secret_name = "pipeshub-arango-password"
  environment               = var.environment

  depends_on = [module.kubernetes]
}

# -----------------------------------------------------------------------------
# Self-hosted: Qdrant on K8s
# -----------------------------------------------------------------------------

module "qdrant" {
  source = "../../../modules/databases/qdrant"

  namespace           = var.app_namespace
  storage_class       = "premium-rwo"
  storage_size        = var.qdrant_storage_size
  cpu_request         = var.qdrant_cpu_request
  cpu_limit           = var.qdrant_cpu_limit
  memory_request      = var.qdrant_memory_request
  memory_limit        = var.qdrant_memory_limit
  api_key_secret_name = "pipeshub-qdrant-apikey"
  node_selector       = { "pipeshub.ai/node-pool" = "data" }
  environment         = var.environment

  depends_on = [module.kubernetes]
}

# -----------------------------------------------------------------------------
# Self-hosted: etcd on K8s (conditional)
# -----------------------------------------------------------------------------

module "etcd" {
  source = "../../../modules/kv-store/etcd"

  enabled       = var.kv_store_type == "etcd"
  namespace     = var.app_namespace
  storage_class = "premium-rwo"
  storage_size  = var.etcd_storage_size
  replica_count = 3
  environment   = var.environment

  depends_on = [module.kubernetes]
}

# -----------------------------------------------------------------------------
# Observability
# -----------------------------------------------------------------------------

module "observability" {
  source = "../../../modules/observability"

  namespace               = "monitoring"
  grafana_admin_password  = var.grafana_admin_password
  retention_days          = 30
  alert_slack_webhook_url = var.alert_slack_webhook_url
  storage_class           = "premium-rwo"

  depends_on = [module.kubernetes]
}

# -----------------------------------------------------------------------------
# Application (PipesHub Helm Release)
# -----------------------------------------------------------------------------

module "application" {
  source = "../../../modules/application"

  namespace        = var.app_namespace
  chart_path       = "${path.module}/../../../../helm/pipeshub-ai"
  image_tag        = var.image_tag
  image_repository = var.image_repository
  replica_count    = var.app_replica_count
  environment      = var.environment

  managed_service_endpoints = {
    mongo_uri            = module.mongodb.connection_string
    redis_host           = module.redis.host
    redis_port           = tostring(module.redis.port)
    redis_password       = module.redis.auth_string
    kafka_brokers        = module.kafka.bootstrap_brokers
    kafka_ssl            = "true"
    kafka_sasl_mechanism = "PLAIN"
    qdrant_host          = module.qdrant.service_name
    qdrant_port          = "6333"
    qdrant_grpc_port     = "6334"
    qdrant_api_key       = ""
    arango_url           = module.arangodb.internal_url
    arango_password      = ""
    etcd_url             = var.kv_store_type == "etcd" ? module.etcd.client_endpoint : ""
    neo4j_uri            = ""
    neo4j_password       = ""
  }

  app_config = {
    secret_key               = var.secret_key
    frontend_public_url      = "https://${var.domain_name}"
    connector_public_backend = var.connector_public_backend
    log_level                = var.log_level
    node_env                 = "production"
    kv_store_type            = var.kv_store_type
    data_store               = var.data_store
  }

  resources = var.app_resources

  ingress_config = {
    enabled         = true
    class_name      = "gce"
    hostname        = var.domain_name
    tls_secret_name = "${var.project_name}-tls"
    annotations     = {}
  }

  depends_on = [
    module.mongodb,
    module.redis,
    module.kafka,
    module.arangodb,
    module.qdrant,
    module.etcd,
    module.secrets,
  ]
}
