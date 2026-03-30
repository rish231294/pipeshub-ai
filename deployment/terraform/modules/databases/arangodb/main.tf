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
# ArangoDB - Single-server deployment via Kubernetes StatefulSet
# Uses helm_release with a raw chart to deploy ArangoDB 3.12.x in standalone
# mode. No official stable Helm chart exists for single-server ArangoDB, so we
# use the kubernetes_manifest approach wrapped in a local Helm chart.
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "arangodb" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
    labels = merge(var.labels, {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "database"
    })
  }
}

resource "kubernetes_secret" "arangodb_root_password" {
  count = var.create_root_password_secret ? 1 : 0

  metadata {
    name      = var.root_password_secret_name
    namespace = var.namespace
    labels = merge(var.labels, {
      "app.kubernetes.io/name"      = "arangodb"
      "app.kubernetes.io/component" = "database"
    })
  }

  data = {
    password = var.root_password
  }

  type = "Opaque"

  depends_on = [kubernetes_namespace.arangodb]
}

resource "helm_release" "arangodb" {
  name       = var.release_name
  namespace  = var.namespace
  chart      = "${path.module}/chart"
  timeout    = var.helm_timeout
  wait       = true
  atomic     = true

  values = [
    yamlencode({
      image = {
        repository = "arangodb"
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

      auth = {
        rootPasswordSecretName = var.root_password_secret_name
        rootPasswordSecretKey  = "password"
      }

      environment = var.environment

      labels = var.labels

      nodeSelector = var.node_selector
      tolerations  = var.tolerations

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
    kubernetes_namespace.arangodb,
    kubernetes_secret.arangodb_root_password,
  ]
}
