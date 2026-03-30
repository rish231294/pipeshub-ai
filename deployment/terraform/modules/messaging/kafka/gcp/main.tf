###############################################################################
# Kafka Module - GCP (Strimzi on GKE)
# Deploys Strimzi Kafka operator via Helm and creates a Kafka cluster CRD
# with SASL/SCRAM authentication, persistent storage, and topic provisioning
###############################################################################

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

locals {
  cluster_name = "${var.project_name}-${var.environment}"

  common_labels = merge(var.labels, {
    environment = var.environment
    project     = var.project_name
  })

  # Determine replica count for ZooKeeper (must be odd, minimum 1)
  zookeeper_replicas = var.broker_count >= 3 ? 3 : 1
}

# -----------------------------------------------------------------------------
# Namespace
# Dedicated namespace for Kafka and Strimzi components
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "kafka" {
  metadata {
    name = var.namespace
    labels = merge(local.common_labels, {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "messaging"
    })
  }
}

# -----------------------------------------------------------------------------
# Strimzi Kafka Operator
# Installed via Helm chart to manage Kafka CRDs on Kubernetes
# -----------------------------------------------------------------------------

resource "helm_release" "strimzi_operator" {
  name       = "strimzi-kafka-operator"
  repository = "https://strimzi.io/charts/"
  chart      = "strimzi-kafka-operator"
  version    = "0.44.0"
  namespace  = var.namespace
  timeout    = 600
  wait       = true
  atomic     = true

  set {
    name  = "watchNamespaces"
    value = "{${var.namespace}}"
  }

  depends_on = [kubernetes_namespace.kafka]
}

# -----------------------------------------------------------------------------
# Kafka Cluster (Strimzi CRD)
# Deploys a Kafka cluster with SASL/SCRAM-SHA-512 authentication
# -----------------------------------------------------------------------------

resource "kubernetes_manifest" "kafka_cluster" {
  manifest = {
    apiVersion = "kafka.strimzi.io/v1beta2"
    kind       = "Kafka"
    metadata = {
      name      = local.cluster_name
      namespace = var.namespace
      labels    = local.common_labels
    }
    spec = {
      kafka = {
        version  = var.kafka_version
        replicas = var.broker_count

        listeners = [
          {
            name = "plain"
            port = 9092
            type = "internal"
            tls  = false
            authentication = {
              type = "scram-sha-512"
            }
          },
          {
            name = "tls"
            port = 9093
            type = "internal"
            tls  = true
            authentication = {
              type = "scram-sha-512"
            }
          },
        ]

        config = {
          "offsets.topic.replication.factor"         = min(var.broker_count, 3)
          "transaction.state.log.replication.factor" = min(var.broker_count, 3)
          "transaction.state.log.min.isr"            = min(var.broker_count, 2)
          "default.replication.factor"               = min(var.broker_count, 3)
          "min.insync.replicas"                      = min(var.broker_count, 2)
          "log.retention.hours"                      = 168
          "log.segment.bytes"                        = 1073741824
          "auto.create.topics.enable"                = false
        }

        storage = {
          type = "persistent-claim"
          size = var.storage_size
          class = var.storage_class
          deleteClaim = var.environment != "prod"
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

        metricsConfig = {
          type = "jmxPrometheusExporter"
          valueFrom = {
            configMapKeyRef = {
              name = "${local.cluster_name}-kafka-metrics"
              key  = "kafka-metrics-config.yml"
            }
          }
        }
      }

      zookeeper = {
        replicas = local.zookeeper_replicas

        storage = {
          type        = "persistent-claim"
          size        = "5Gi"
          class       = var.storage_class
          deleteClaim = var.environment != "prod"
        }

        resources = {
          requests = {
            cpu    = "250m"
            memory = "512Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "1Gi"
          }
        }
      }

      entityOperator = {
        topicOperator = {}
        userOperator  = {}
      }
    }
  }

  depends_on = [helm_release.strimzi_operator]
}

# -----------------------------------------------------------------------------
# Kafka Metrics ConfigMap
# Prometheus JMX exporter configuration for Kafka broker metrics
# -----------------------------------------------------------------------------

resource "kubernetes_config_map" "kafka_metrics" {
  metadata {
    name      = "${local.cluster_name}-kafka-metrics"
    namespace = var.namespace
    labels    = local.common_labels
  }

  data = {
    "kafka-metrics-config.yml" = yamlencode({
      lowercaseOutputName = true
      rules = [
        {
          pattern = "kafka.server<type=(.+), name=(.+), clientId=(.+), topic=(.+), partition=(.*)><>Value"
          name    = "kafka_server_$1_$2"
          type    = "GAUGE"
          labels = {
            clientId  = "$3"
            topic     = "$4"
            partition = "$5"
          }
        },
        {
          pattern = "kafka.server<type=(.+), name=(.+)><>Value"
          name    = "kafka_server_$1_$2"
          type    = "GAUGE"
        },
      ]
    })
  }

  depends_on = [kubernetes_namespace.kafka]
}

# -----------------------------------------------------------------------------
# Kafka User (SASL/SCRAM-SHA-512)
# Application-level user for PipesHub services
# -----------------------------------------------------------------------------

resource "kubernetes_manifest" "kafka_user" {
  manifest = {
    apiVersion = "kafka.strimzi.io/v1beta2"
    kind       = "KafkaUser"
    metadata = {
      name      = "${local.cluster_name}-app"
      namespace = var.namespace
      labels = merge(local.common_labels, {
        "strimzi.io/cluster" = local.cluster_name
      })
    }
    spec = {
      authentication = {
        type = "scram-sha-512"
      }
      authorization = {
        type = "simple"
        acls = [
          {
            resource = {
              type        = "topic"
              name        = "*"
              patternType = "literal"
            }
            operations = ["Read", "Write", "Describe", "Create"]
            host       = "*"
          },
          {
            resource = {
              type        = "group"
              name        = "*"
              patternType = "literal"
            }
            operations = ["Read", "Describe"]
            host       = "*"
          },
        ]
      }
    }
  }

  depends_on = [kubernetes_manifest.kafka_cluster]
}

# -----------------------------------------------------------------------------
# Kafka Topics
# Create topics defined in the topics variable via Strimzi KafkaTopic CRD
# -----------------------------------------------------------------------------

resource "kubernetes_manifest" "kafka_topics" {
  for_each = { for topic in var.topics : topic.name => topic }

  manifest = {
    apiVersion = "kafka.strimzi.io/v1beta2"
    kind       = "KafkaTopic"
    metadata = {
      name      = each.value.name
      namespace = var.namespace
      labels = merge(local.common_labels, {
        "strimzi.io/cluster" = local.cluster_name
      })
    }
    spec = {
      partitions = each.value.partitions
      replicas   = min(each.value.replicas, var.broker_count)
      config     = each.value.config
    }
  }

  depends_on = [kubernetes_manifest.kafka_cluster]
}
