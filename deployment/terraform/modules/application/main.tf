terraform {
  required_version = ">= 1.5.0"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.25.0"
    }
  }
}

# -----------------------------------------------------------------------------
# PipesHub AI Application Deployment
# Deploys the PipesHub AI platform using the existing Helm chart. When managed
# cloud services (e.g., DocumentDB, ElastiCache, Confluent) are used, the
# corresponding in-cluster sub-chart deployments are disabled and the managed
# endpoints are injected as environment variables.
# -----------------------------------------------------------------------------

locals {
  # Determine which in-cluster components to disable when managed endpoints
  # are provided. A non-empty managed endpoint means we use the managed service
  # instead of deploying the component in-cluster.
  use_managed_mongo  = var.managed_service_endpoints.mongo_uri != ""
  use_managed_redis  = var.managed_service_endpoints.redis_host != ""
  use_managed_kafka  = var.managed_service_endpoints.kafka_brokers != ""
  use_managed_arango = var.managed_service_endpoints.arango_url != ""
  use_managed_qdrant = var.managed_service_endpoints.qdrant_host != ""
  use_managed_etcd   = var.managed_service_endpoints.etcd_url != ""
  use_managed_neo4j  = var.managed_service_endpoints.neo4j_uri != ""

  # Build the set of Helm values that wire managed service endpoints
  managed_env_values = merge(
    # MongoDB
    local.use_managed_mongo ? {
      "mongodb.enabled" = false
    } : {},

    # Redis
    local.use_managed_redis ? {
      "redis.enabled" = false
    } : {},

    # Kafka (deployed via sub-chart in the main chart)
    local.use_managed_kafka ? {} : {},

    # ArangoDB (deployed as separate StatefulSet in the chart)
    local.use_managed_arango ? {} : {},
  )
}

resource "kubernetes_namespace" "application" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
    labels = merge(var.labels, {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "pipeshub-ai"
    })
  }
}

resource "helm_release" "pipeshub_ai" {
  name             = var.release_name
  namespace        = var.namespace
  chart            = var.chart_path
  timeout          = var.helm_timeout
  wait             = true
  atomic           = true
  create_namespace = false

  # Optional environment-specific values file
  dynamic "set" {
    for_each = var.values_file != "" ? [1] : []
    content {
      name  = "__values_file_marker"
      value = "true"
    }
  }

  values = compact([
    # Base values
    yamlencode({
      replicaCount = var.replica_count

      image = {
        repository = var.image_repository
        tag        = var.image_tag
        pullPolicy = var.image_pull_policy
      }

      # Application configuration
      config = {
        nodeEnv              = var.app_config.node_env
        logLevel             = var.app_config.log_level
        allowedOrigins       = var.app_config.allowed_origins
        connectorPublicBackend = var.app_config.connector_public_backend
        frontendPublicUrl    = var.app_config.frontend_public_url
      }

      secretKey = var.app_config.secret_key

      # Resources
      resources = {
        requests = {
          cpu    = var.resources.cpu_request
          memory = var.resources.memory_request
        }
        limits = {
          cpu    = var.resources.cpu_limit
          memory = var.resources.memory_limit
        }
      }

      # Persistence
      persistence = {
        enabled      = true
        storageClass = var.storage_class
        size         = var.storage_size
      }

      # Managed service flags -- tells the Helm chart which services are
      # provided externally (true) vs deployed in-cluster (false).
      managed = {
        kafka   = local.use_managed_kafka
        mongodb = local.use_managed_mongo
        redis   = local.use_managed_redis
        etcd    = local.use_managed_etcd
        arango  = local.use_managed_arango
        qdrant  = local.use_managed_qdrant
        neo4j   = local.use_managed_neo4j
      }

      # External service endpoints (populated when managed.<service> is true)
      external = {
        kafka = local.use_managed_kafka ? {
          brokers       = var.managed_service_endpoints.kafka_brokers
          ssl           = tostring(var.managed_service_endpoints.kafka_ssl)
          saslMechanism = var.managed_service_endpoints.kafka_sasl_mechanism
          username      = var.managed_service_endpoints.kafka_username
        } : {}
        mongodb = local.use_managed_mongo ? {
          uri    = var.managed_service_endpoints.mongo_uri
          dbName = "es"
        } : {}
        redis = local.use_managed_redis ? {
          host     = var.managed_service_endpoints.redis_host
          port     = tostring(var.managed_service_endpoints.redis_port)
          password = var.managed_service_endpoints.redis_password
        } : {}
        etcd = local.use_managed_etcd ? {
          url  = var.managed_service_endpoints.etcd_url
          host = var.managed_service_endpoints.etcd_host
        } : {}
        arango = local.use_managed_arango ? {
          url      = var.managed_service_endpoints.arango_url
          dbName   = "es"
          username = "root"
        } : {}
        qdrant = local.use_managed_qdrant ? {
          host     = var.managed_service_endpoints.qdrant_host
          port     = tostring(var.managed_service_endpoints.qdrant_port)
          grpcPort = tostring(var.managed_service_endpoints.qdrant_grpc_port)
        } : {}
        neo4j = local.use_managed_neo4j ? {
          uri      = var.managed_service_endpoints.neo4j_uri
          username = var.managed_service_endpoints.neo4j_username
          database = var.managed_service_endpoints.neo4j_database
        } : {}
      }

      # Pod labels
      podLabels = merge(var.labels, {
        "app.kubernetes.io/part-of" = "pipeshub-ai"
        "environment"               = var.environment
      })

      # Ingress configuration
      ingress = {
        enabled   = var.ingress_config.enabled
        className = var.ingress_config.class_name
        annotations = var.ingress_config.annotations
        hosts = var.ingress_config.hostname != "" ? [
          {
            host = var.ingress_config.hostname
            paths = [
              {
                path        = "/"
                pathType    = "ImplementationSpecific"
                port        = 3000
                serviceName = var.release_name
              }
            ]
          }
        ] : []
        tls = var.ingress_config.tls_secret_name != "" ? [
          {
            secretName = var.ingress_config.tls_secret_name
            hosts      = [var.ingress_config.hostname]
          }
        ] : []
      }

      # -- In-cluster component overrides --
      # When managed services are used, disable the in-cluster deployment
      # and inject the managed endpoint instead.

      # MongoDB
      mongodb = local.use_managed_mongo ? {
        enabled = false
      } : {
        replicaCount = 1
        auth = {
          enabled = false
        }
        persistence = {
          enabled      = true
          storageClass = var.storage_class
        }
      }

      # Redis
      redis = local.use_managed_redis ? {
        enabled = false
      } : {
        auth = {
          enabled = false
        }
        persistence = {
          enabled      = true
          storageClass = var.storage_class
        }
      }

      # ArangoDB -- only set in-cluster config when not managed
      arango = local.use_managed_arango ? {} : {
        image = {
          repository = "arangodb"
          tag        = "3.12.4"
        }
        resources = {
          limits = {
            cpu    = var.resources.cpu_limit
            memory = "1Gi"
          }
          requests = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }
        persistence = {
          enabled      = true
          size         = "10Gi"
          storageClass = var.storage_class
        }
        auth = {
          enabled      = true
          rootPassword = "root"
        }
      }

      # Qdrant -- only set in-cluster config when not managed
      qdrant = local.use_managed_qdrant ? {} : {
        image = {
          repository = "qdrant/qdrant"
          tag        = "v1.15"
        }
        persistence = {
          enabled      = true
          size         = "10Gi"
          storageClass = var.storage_class
        }
      }

      # etcd -- only set in-cluster config when not managed
      etcd = local.use_managed_etcd ? {} : {
        image = {
          repository = "quay.io/coreos/etcd"
          tag        = "v3.5.17"
        }
        persistence = {
          enabled      = true
          size         = "1Gi"
          storageClass = var.storage_class
        }
      }

      # Neo4j -- only set in-cluster config when not managed and dataStore is neo4j
      neo4j = (!local.use_managed_neo4j && var.app_config.data_store == "neo4j") ? {
        image = {
          repository = "neo4j"
          tag        = "5.26.0"
        }
        persistence = {
          enabled      = true
          size         = "10Gi"
          storageClass = var.storage_class
        }
      } : {}
    }),

    # Environment-specific values file (if provided)
    var.values_file != "" ? file(var.values_file) : null,
  ])

  # Inject managed service endpoints as individual set values so they override
  # any values file. These map to the env vars in the deployment template.
  # MongoDB
  dynamic "set_sensitive" {
    for_each = local.use_managed_mongo ? [1] : []
    content {
      name  = "config.mongoUri"
      value = var.managed_service_endpoints.mongo_uri
    }
  }

  # Redis
  dynamic "set" {
    for_each = local.use_managed_redis ? [1] : []
    content {
      name  = "config.redisHost"
      value = var.managed_service_endpoints.redis_host
    }
  }

  dynamic "set" {
    for_each = local.use_managed_redis ? [1] : []
    content {
      name  = "config.redisPort"
      value = tostring(var.managed_service_endpoints.redis_port)
    }
  }

  dynamic "set_sensitive" {
    for_each = local.use_managed_redis && var.managed_service_endpoints.redis_password != "" ? [1] : []
    content {
      name  = "config.redisPassword"
      value = var.managed_service_endpoints.redis_password
    }
  }

  # Kafka
  dynamic "set" {
    for_each = local.use_managed_kafka ? [1] : []
    content {
      name  = "config.kafkaBrokers"
      value = var.managed_service_endpoints.kafka_brokers
    }
  }

  dynamic "set" {
    for_each = local.use_managed_kafka && var.managed_service_endpoints.kafka_ssl ? [1] : []
    content {
      name  = "config.kafkaSsl"
      value = "true"
    }
  }

  dynamic "set" {
    for_each = local.use_managed_kafka && var.managed_service_endpoints.kafka_sasl_mechanism != "" ? [1] : []
    content {
      name  = "config.kafkaSaslMechanism"
      value = var.managed_service_endpoints.kafka_sasl_mechanism
    }
  }

  # ArangoDB
  dynamic "set" {
    for_each = local.use_managed_arango ? [1] : []
    content {
      name  = "config.arangoUrl"
      value = var.managed_service_endpoints.arango_url
    }
  }

  dynamic "set_sensitive" {
    for_each = local.use_managed_arango && var.managed_service_endpoints.arango_password != "" ? [1] : []
    content {
      name  = "config.arangoPassword"
      value = var.managed_service_endpoints.arango_password
    }
  }

  # Qdrant
  dynamic "set" {
    for_each = local.use_managed_qdrant ? [1] : []
    content {
      name  = "config.qdrantHost"
      value = var.managed_service_endpoints.qdrant_host
    }
  }

  dynamic "set" {
    for_each = local.use_managed_qdrant ? [1] : []
    content {
      name  = "config.qdrantPort"
      value = tostring(var.managed_service_endpoints.qdrant_port)
    }
  }

  dynamic "set" {
    for_each = local.use_managed_qdrant ? [1] : []
    content {
      name  = "config.qdrantGrpcPort"
      value = tostring(var.managed_service_endpoints.qdrant_grpc_port)
    }
  }

  dynamic "set_sensitive" {
    for_each = local.use_managed_qdrant && var.managed_service_endpoints.qdrant_api_key != "" ? [1] : []
    content {
      name  = "config.qdrantApiKey"
      value = var.managed_service_endpoints.qdrant_api_key
    }
  }

  # etcd
  dynamic "set" {
    for_each = local.use_managed_etcd ? [1] : []
    content {
      name  = "config.etcdUrl"
      value = var.managed_service_endpoints.etcd_url
    }
  }

  # Neo4j
  dynamic "set" {
    for_each = local.use_managed_neo4j ? [1] : []
    content {
      name  = "config.neo4jUri"
      value = var.managed_service_endpoints.neo4j_uri
    }
  }

  dynamic "set_sensitive" {
    for_each = local.use_managed_neo4j && var.managed_service_endpoints.neo4j_password != "" ? [1] : []
    content {
      name  = "config.neo4jPassword"
      value = var.managed_service_endpoints.neo4j_password
    }
  }

  # KV store type
  dynamic "set" {
    for_each = var.app_config.kv_store_type != "" ? [1] : []
    content {
      name  = "config.kvStoreType"
      value = var.app_config.kv_store_type
    }
  }

  # Data store type
  dynamic "set" {
    for_each = var.app_config.data_store != "" ? [1] : []
    content {
      name  = "config.dataStore"
      value = var.app_config.data_store
    }
  }

  depends_on = [kubernetes_namespace.application]
}
