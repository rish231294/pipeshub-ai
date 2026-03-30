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
# Qdrant - High-performance vector database
# Deploys Qdrant via the official qdrant/qdrant Helm chart with performance
# tuning for production workloads (search threads, segment count, WAL, memmap).
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "qdrant" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
    labels = merge(var.labels, {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "vector-database"
    })
  }
}

resource "kubernetes_secret" "qdrant_api_key" {
  count = var.create_api_key_secret ? 1 : 0

  metadata {
    name      = var.api_key_secret_name
    namespace = var.namespace
    labels = merge(var.labels, {
      "app.kubernetes.io/name"      = "qdrant"
      "app.kubernetes.io/component" = "vector-database"
    })
  }

  data = {
    api-key = var.api_key
  }

  type = "Opaque"

  depends_on = [kubernetes_namespace.qdrant]
}

resource "helm_release" "qdrant" {
  name             = var.release_name
  namespace        = var.namespace
  repository       = "https://qdrant.github.io/qdrant-helm"
  chart            = "qdrant"
  version          = var.chart_version
  timeout          = var.helm_timeout
  wait             = true
  atomic           = true
  create_namespace = false

  values = [
    yamlencode({
      replicaCount = var.replica_count

      image = {
        repository = "qdrant/qdrant"
        tag        = var.image_tag
        pullPolicy = "IfNotPresent"
      }

      resources = {
        requests = {
          cpu    = var.cpu_request
          memory = var.memory_request
        }
        limits = {
          cpu    = var.cpu_limit
          memory = var.memory_limit
        }
      }

      persistence = {
        enabled      = true
        storageClass = var.storage_class
        size         = var.storage_size
        accessModes  = ["ReadWriteOnce"]
      }

      # API key authentication
      apiKey = true
      existingApiKeySecret     = var.api_key_secret_name
      existingApiKeySecretKey  = "api-key"

      # Performance tuning configuration
      config = {
        storage = {
          performance = {
            max_search_threads = 0
          }
          optimizers = {
            default_segment_number = var.optimizer_segment_number
            memmap_threshold       = var.optimizer_memmap_threshold
          }
          wal = {
            wal_capacity_mb = var.wal_capacity_mb
          }
        }
      }

      # Node scheduling
      nodeSelector = var.node_selector
      tolerations  = var.tolerations

      # Pod affinity for data node groups
      affinity = length(var.node_selector) > 0 ? {
        nodeAffinity = {
          preferredDuringSchedulingIgnoredDuringExecution = [
            {
              weight = 100
              preference = {
                matchExpressions = [
                  for key, value in var.node_selector : {
                    key      = key
                    operator = "In"
                    values   = [value]
                  }
                ]
              }
            }
          ]
        }
      } : {}

      # Service configuration
      service = {
        type = "ClusterIP"
        ports = {
          http = 6333
          grpc = 6334
        }
      }

      podLabels = merge(var.labels, {
        "app.kubernetes.io/component" = "vector-database"
        "app.kubernetes.io/part-of"   = "pipeshub-ai"
      })

      podSecurityContext = {
        runAsUser           = 1000
        fsGroup             = 1000
        fsGroupChangePolicy = "OnRootMismatch"
        runAsNonRoot        = true
        seccompProfile = {
          type = "RuntimeDefault"
        }
      }

      securityContext = {
        allowPrivilegeEscalation = false
        capabilities = {
          drop = ["ALL"]
        }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.qdrant,
    kubernetes_secret.qdrant_api_key,
  ]
}
