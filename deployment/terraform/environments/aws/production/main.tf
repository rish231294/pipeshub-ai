# -----------------------------------------------------------------------------
# PipesHub AI - AWS Production Environment
# Main composition file that wires all modules together
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
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

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
    }
  }
}

# Configure Kubernetes provider after EKS is created
provider "kubernetes" {
  host                   = module.kubernetes.cluster_endpoint
  cluster_ca_certificate = base64decode(module.kubernetes.cluster_certificate_authority)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.kubernetes.cluster_name]
  }
}

# Configure Helm provider after EKS is created
provider "helm" {
  kubernetes {
    host                   = module.kubernetes.cluster_endpoint
    cluster_ca_certificate = base64decode(module.kubernetes.cluster_certificate_authority)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.kubernetes.cluster_name]
    }
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
  source = "../../../modules/networking/aws"

  environment           = var.environment
  project_name          = var.project_name
  region                = var.region
  vpc_cidr              = var.vpc_cidr
  availability_zones    = var.availability_zones
  enable_nat_gateway_ha = var.environment != "dev"
  tags                  = local.common_tags
}

# -----------------------------------------------------------------------------
# Kubernetes (EKS)
# -----------------------------------------------------------------------------

module "kubernetes" {
  source = "../../../modules/kubernetes/aws"

  environment        = var.environment
  project_name       = var.project_name
  cluster_name       = "${var.project_name}-${var.environment}"
  cluster_version    = var.eks_cluster_version
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  node_groups        = var.node_groups
  tags               = local.common_tags
}

# -----------------------------------------------------------------------------
# Managed MongoDB (DocumentDB)
# -----------------------------------------------------------------------------

module "mongodb" {
  source = "../../../modules/databases/mongodb/aws"

  environment                = var.environment
  project_name               = var.project_name
  cluster_identifier         = "${var.project_name}-${var.environment}-docdb"
  instance_class             = var.mongodb_instance_class
  instance_count             = var.mongodb_instance_count
  vpc_id                     = module.networking.vpc_id
  database_subnet_ids        = module.networking.database_subnet_ids
  allowed_security_group_ids = [module.kubernetes.cluster_security_group_id]
  tags                       = local.common_tags
}

# -----------------------------------------------------------------------------
# Managed Redis (ElastiCache)
# -----------------------------------------------------------------------------

module "redis" {
  source = "../../../modules/databases/redis/aws"

  environment                = var.environment
  project_name               = var.project_name
  replication_group_id       = "${var.project_name}-${var.environment}"
  node_type                  = var.redis_node_type
  num_cache_clusters         = var.redis_num_cache_clusters
  vpc_id                     = module.networking.vpc_id
  database_subnet_ids        = module.networking.database_subnet_ids
  allowed_security_group_ids = [module.kubernetes.cluster_security_group_id]
  tags                       = local.common_tags
}

# -----------------------------------------------------------------------------
# Managed Kafka (MSK)
# -----------------------------------------------------------------------------

module "kafka" {
  source = "../../../modules/messaging/kafka/aws"

  environment                = var.environment
  project_name               = var.project_name
  cluster_name               = "${var.project_name}-${var.environment}"
  broker_instance_type       = var.kafka_broker_instance_type
  broker_count               = var.kafka_broker_count
  vpc_id                     = module.networking.vpc_id
  database_subnet_ids        = module.networking.database_subnet_ids
  allowed_security_group_ids = [module.kubernetes.cluster_security_group_id]
  tags                       = local.common_tags
}

# -----------------------------------------------------------------------------
# Secrets Management
# -----------------------------------------------------------------------------

module "secrets" {
  source = "../../../modules/secrets/aws"

  environment       = var.environment
  project_name      = var.project_name
  oidc_provider_arn = module.kubernetes.oidc_provider_arn
  oidc_provider_url = module.kubernetes.oidc_provider_url
  eks_namespace     = var.app_namespace
  tags              = local.common_tags
}

# -----------------------------------------------------------------------------
# DNS & TLS
# -----------------------------------------------------------------------------

module "dns" {
  source = "../../../modules/dns/aws"

  environment       = var.environment
  project_name      = var.project_name
  domain_name       = var.domain_name
  zone_id           = var.route53_zone_id
  create_zone       = var.create_dns_zone
  cluster_name      = module.kubernetes.cluster_name
  oidc_provider_arn = module.kubernetes.oidc_provider_arn
  vpc_id            = module.networking.vpc_id
  region            = var.region
  tags              = local.common_tags
}

# -----------------------------------------------------------------------------
# Object Storage (S3)
# -----------------------------------------------------------------------------

module "storage" {
  source = "../../../modules/storage/aws"

  environment          = var.environment
  project_name         = var.project_name
  bucket_name          = "${var.project_name}-${var.environment}-documents"
  cors_allowed_origins = var.cors_allowed_origins
  oidc_provider_arn    = module.kubernetes.oidc_provider_arn
  oidc_provider_url    = module.kubernetes.oidc_provider_url
  eks_namespace        = var.app_namespace
  service_account_name = "pipeshub-ai"
  tags                 = local.common_tags
}

# -----------------------------------------------------------------------------
# Self-hosted: ArangoDB on K8s
# -----------------------------------------------------------------------------

module "arangodb" {
  source = "../../../modules/databases/arangodb"

  namespace                 = var.app_namespace
  storage_class             = "gp3"
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
  storage_class       = "gp3"
  storage_size        = var.qdrant_storage_size
  cpu_request         = var.qdrant_cpu_request
  cpu_limit           = var.qdrant_cpu_limit
  memory_request      = var.qdrant_memory_request
  memory_limit        = var.qdrant_memory_limit
  api_key_secret_name = "pipeshub-qdrant-apikey"
  node_selector       = { "pipeshub.ai/node-group" = "data" }
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
  storage_class = "gp3"
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
  storage_class             = "gp3"

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
    redis_host           = module.redis.primary_endpoint
    redis_port           = "6379"
    redis_password       = ""
    kafka_brokers        = module.kafka.bootstrap_brokers_tls
    kafka_ssl            = "true"
    kafka_sasl_mechanism = "SCRAM-SHA-512"
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
    class_name      = "alb"
    hostname        = var.domain_name
    tls_secret_name = ""
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
