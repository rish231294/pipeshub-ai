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
# Neo4j - Optional graph database deployment
# Deploys Neo4j Community Edition via the official neo4j/neo4j Helm chart.
# This module is conditionally deployed based on the `enabled` variable, which
# should be set to true only when DATA_STORE=neo4j is configured in the app.
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "neo4j" {
  count = var.enabled && var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
    labels = merge(var.labels, {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "database"
    })
  }
}

resource "kubernetes_secret" "neo4j_auth" {
  count = var.enabled && var.create_auth_secret ? 1 : 0

  metadata {
    name      = var.auth_secret_name
    namespace = var.namespace
    labels = merge(var.labels, {
      "app.kubernetes.io/name"      = "neo4j"
      "app.kubernetes.io/component" = "database"
    })
  }

  data = {
    NEO4J_AUTH = "neo4j/${var.neo4j_password}"
    username   = "neo4j"
    password   = var.neo4j_password
  }

  type = "Opaque"

  depends_on = [kubernetes_namespace.neo4j]
}

resource "helm_release" "neo4j" {
  count = var.enabled ? 1 : 0

  name             = var.release_name
  namespace        = var.namespace
  repository       = "https://helm.neo4j.com/neo4j"
  chart            = "neo4j"
  version          = var.chart_version
  timeout          = var.helm_timeout
  wait             = true
  atomic           = true
  create_namespace = false

  # Neo4j standalone mode
  set {
    name  = "neo4j.name"
    value = var.release_name
  }

  set {
    name  = "neo4j.edition"
    value = "community"
  }

  # Image configuration
  set {
    name  = "image.customImage"
    value = "neo4j:${var.image_tag}"
  }

  # Authentication via existing secret
  set {
    name  = "neo4j.passwordFromSecret"
    value = var.auth_secret_name
  }

  # Persistence
  set {
    name  = "volumes.data.mode"
    value = "dynamic"
  }

  set {
    name  = "volumes.data.dynamic.storageClassName"
    value = var.storage_class
  }

  set {
    name  = "volumes.data.dynamic.requests.storage"
    value = var.storage_size
  }

  # Resources
  set {
    name  = "neo4j.resources.requests.cpu"
    value = var.cpu_request
  }

  set {
    name  = "neo4j.resources.requests.memory"
    value = var.memory_request
  }

  set {
    name  = "neo4j.resources.limits.cpu"
    value = var.cpu_limit
  }

  set {
    name  = "neo4j.resources.limits.memory"
    value = var.memory_limit
  }

  # APOC plugin and memory configuration
  values = [
    yamlencode({
      env = {
        NEO4J_PLUGINS                                = "[\"apoc\"]"
        NEO4J_dbms_security_procedures_unrestricted  = "apoc.*"
        NEO4J_dbms_memory_heap_initial__size          = var.heap_initial_size
        NEO4J_dbms_memory_heap_max__size              = var.heap_max_size
        NEO4J_dbms_memory_pagecache_size             = var.pagecache_size
      }

      services = {
        neo4j = {
          enabled = true
          spec = {
            type = "ClusterIP"
          }
        }
      }

      podSpec = {
        nodeSelector = var.node_selector
        tolerations  = var.tolerations
      }

      commonLabels = merge(var.labels, {
        "app.kubernetes.io/component" = "database"
        "app.kubernetes.io/part-of"   = "pipeshub-ai"
      })
    })
  ]

  depends_on = [
    kubernetes_namespace.neo4j,
    kubernetes_secret.neo4j_auth,
  ]
}
