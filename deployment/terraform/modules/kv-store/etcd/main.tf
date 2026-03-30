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
# etcd - Distributed key-value store for configuration management
# Deploys etcd via the Bitnami Helm chart. Conditionally deployed based on the
# KV_STORE_TYPE configuration. Uses 1 replica for dev, 3 for production HA.
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "etcd" {
  count = var.enabled && var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
    labels = merge(var.labels, {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "kv-store"
    })
  }
}

resource "helm_release" "etcd" {
  count = var.enabled ? 1 : 0

  name             = var.release_name
  namespace        = var.namespace
  repository       = "https://charts.bitnami.com/bitnami"
  chart            = "etcd"
  version          = var.chart_version
  timeout          = var.helm_timeout
  wait             = true
  atomic           = true
  create_namespace = false

  values = [
    yamlencode({
      image = {
        tag = var.image_tag
      }

      replicaCount = var.replica_count

      auth = {
        rbac = {
          create            = var.auth_enabled
          allowNoneAuthentication = !var.auth_enabled
        }
        token = {
          enabled = var.auth_enabled
        }
      }

      persistence = {
        enabled      = true
        storageClass = var.storage_class
        size         = var.storage_size
        accessModes  = ["ReadWriteOnce"]
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

      # Auto compaction to prevent unbounded growth
      autoCompactionMode      = "periodic"
      autoCompactionRetention = var.auto_compaction_retention

      # Snapshot count for faster recovery
      extraEnvVars = [
        {
          name  = "ETCD_SNAPSHOT_COUNT"
          value = tostring(var.snapshot_count)
        },
        {
          name  = "ETCD_QUOTA_BACKEND_BYTES"
          value = tostring(var.quota_backend_bytes)
        }
      ]

      nodeSelector = var.node_selector
      tolerations  = var.tolerations

      commonLabels = merge(var.labels, {
        "app.kubernetes.io/component" = "kv-store"
        "app.kubernetes.io/part-of"   = "pipeshub-ai"
      })

      podSecurityContext = {
        enabled    = true
        runAsUser  = 1000
        fsGroup    = 1000
        runAsNonRoot = true
        seccompProfile = {
          type = "RuntimeDefault"
        }
      }

      containerSecurityContext = {
        enabled                  = true
        allowPrivilegeEscalation = false
        capabilities = {
          drop = ["ALL"]
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace.etcd]
}
