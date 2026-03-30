# -----------------------------------------------------------------------------
# PipesHub AI - Azure Staging Environment
# Main composition file that wires all modules together
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
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

provider "azurerm" {
  features {}
}

# Configure Kubernetes provider after AKS is created
provider "kubernetes" {
  host                   = module.kubernetes.cluster_endpoint
  cluster_ca_certificate = base64decode(module.kubernetes.cluster_certificate_authority)
  client_certificate     = base64decode(module.kubernetes.client_certificate)
  client_key             = base64decode(module.kubernetes.client_key)
}

# Configure Helm provider after AKS is created
provider "helm" {
  kubernetes {
    host                   = module.kubernetes.cluster_endpoint
    cluster_ca_certificate = base64decode(module.kubernetes.cluster_certificate_authority)
    client_certificate     = base64decode(module.kubernetes.client_certificate)
    client_key             = base64decode(module.kubernetes.client_key)
  }
}

locals {
  common_tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
  }
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------

module "networking" {
  source = "../../../modules/networking/azure"

  environment    = var.environment
  project_name   = var.project_name
  location       = var.location
  vnet_cidr      = var.vnet_cidr
  tags           = local.common_tags
}

# -----------------------------------------------------------------------------
# Kubernetes (AKS)
# -----------------------------------------------------------------------------

module "kubernetes" {
  source = "../../../modules/kubernetes/azure"

  environment        = var.environment
  project_name       = var.project_name
  location           = var.location
  cluster_name       = "${var.project_name}-${var.environment}"
  kubernetes_version = var.aks_kubernetes_version
  vnet_id            = module.networking.vnet_id
  subnet_id          = module.networking.aks_subnet_id
  node_pools         = var.node_pools
  tags               = local.common_tags
}

# -----------------------------------------------------------------------------
# Managed MongoDB (Cosmos DB for MongoDB)
# -----------------------------------------------------------------------------

module "mongodb" {
  source = "../../../modules/databases/mongodb/azure"

  environment          = var.environment
  project_name         = var.project_name
  location             = var.location
  resource_group_name  = module.networking.resource_group_name
  cosmos_db_offer_type = var.cosmos_db_offer_type
  cosmos_db_kind       = "MongoDB"
  throughput           = var.cosmos_db_throughput
  vnet_id              = module.networking.vnet_id
  subnet_id            = module.networking.database_subnet_id
  tags                 = local.common_tags
}

# -----------------------------------------------------------------------------
# Managed Redis (Azure Cache for Redis)
# -----------------------------------------------------------------------------

module "redis" {
  source = "../../../modules/databases/redis/azure"

  environment         = var.environment
  project_name        = var.project_name
  location            = var.location
  resource_group_name = module.networking.resource_group_name
  sku_name            = var.redis_sku_name
  family              = var.redis_family
  capacity            = var.redis_capacity
  vnet_id             = module.networking.vnet_id
  subnet_id           = module.networking.database_subnet_id
  tags                = local.common_tags
}

# -----------------------------------------------------------------------------
# Managed Kafka (Azure Event Hubs with Kafka protocol)
# -----------------------------------------------------------------------------

module "kafka" {
  source = "../../../modules/messaging/kafka/azure"

  environment         = var.environment
  project_name        = var.project_name
  location            = var.location
  resource_group_name = module.networking.resource_group_name
  sku                 = var.eventhub_sku
  capacity            = var.eventhub_capacity
  vnet_id             = module.networking.vnet_id
  subnet_id           = module.networking.database_subnet_id
  tags                = local.common_tags
}

# -----------------------------------------------------------------------------
# Secrets Management
# -----------------------------------------------------------------------------

module "secrets" {
  source = "../../../modules/secrets/azure"

  environment         = var.environment
  project_name        = var.project_name
  location            = var.location
  resource_group_name = module.networking.resource_group_name
  aks_identity_id     = module.kubernetes.kubelet_identity_object_id
  tags                = local.common_tags
}

# -----------------------------------------------------------------------------
# DNS & TLS
# -----------------------------------------------------------------------------

module "dns" {
  source = "../../../modules/dns/azure"

  environment         = var.environment
  project_name        = var.project_name
  domain_name         = var.domain_name
  resource_group_name = module.networking.resource_group_name
  create_zone         = var.create_dns_zone
  tags                = local.common_tags
}

# -----------------------------------------------------------------------------
# Object Storage (Azure Blob Storage)
# -----------------------------------------------------------------------------

module "storage" {
  source = "../../../modules/storage/azure"

  environment          = var.environment
  project_name         = var.project_name
  location             = var.location
  resource_group_name  = module.networking.resource_group_name
  container_name       = "${var.project_name}-${var.environment}-documents"
  cors_allowed_origins = var.cors_allowed_origins
  aks_identity_id      = module.kubernetes.kubelet_identity_object_id
  tags                 = local.common_tags
}

# -----------------------------------------------------------------------------
# Self-hosted: ArangoDB on K8s
# -----------------------------------------------------------------------------

module "arangodb" {
  source = "../../../modules/databases/arangodb"

  namespace                 = var.app_namespace
  storage_class             = "managed-premium"
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
  storage_class       = "managed-premium"
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
  storage_class = "managed-premium"
  storage_size  = var.etcd_storage_size
  replica_count = var.environment == "production" ? 3 : 1
  environment   = var.environment

  depends_on = [module.kubernetes]
}

# -----------------------------------------------------------------------------
# Observability
# -----------------------------------------------------------------------------

module "observability" {
  source = "../../../modules/observability"

  namespace                 = "monitoring"
  grafana_admin_password    = var.grafana_admin_password
  retention_days            = var.environment == "production" ? 30 : 7
  alert_slack_webhook_url   = var.alert_slack_webhook_url
  storage_class             = "managed-premium"

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
    redis_host           = module.redis.hostname
    redis_port           = tostring(module.redis.ssl_port)
    redis_password       = module.redis.primary_access_key
    kafka_brokers        = module.kafka.kafka_endpoint
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
    class_name      = "nginx"
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
