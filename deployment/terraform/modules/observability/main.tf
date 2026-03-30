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
# Observability Stack
# - kube-prometheus-stack: Prometheus + Grafana + Alertmanager
# - loki-stack: Loki (log aggregation) + Promtail (log shipping)
# Provides metrics collection, dashboarding, alerting, and log aggregation
# for the PipesHub AI platform.
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "observability" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
    labels = merge(var.labels, {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "observability"
    })
  }
}

# ---------------------------------------------------------------------------
# kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
# ---------------------------------------------------------------------------

resource "helm_release" "kube_prometheus_stack" {
  name             = var.prometheus_release_name
  namespace        = var.namespace
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = var.prometheus_chart_version
  timeout          = var.helm_timeout
  wait             = true
  atomic           = false # CRDs can cause issues with atomic
  create_namespace = false

  values = [
    yamlencode({
      # -- Global labels
      commonLabels = merge(var.labels, {
        "app.kubernetes.io/part-of" = "pipeshub-ai"
      })

      # -- Prometheus configuration
      prometheus = {
        prometheusSpec = {
          retention         = "${var.retention_days}d"
          retentionSize     = var.prometheus_retention_size

          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = var.storage_class
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = var.prometheus_storage_size
                  }
                }
              }
            }
          }

          resources = {
            requests = {
              cpu    = var.prometheus_cpu_request
              memory = var.prometheus_memory_request
            }
            limits = {
              cpu    = var.prometheus_cpu_limit
              memory = var.prometheus_memory_limit
            }
          }

          nodeSelector = var.node_selector
          tolerations  = var.tolerations

          # Scrape PipesHub services by default
          additionalScrapeConfigs = [
            {
              job_name        = "pipeshub-ai"
              scrape_interval = "30s"
              kubernetes_sd_configs = [
                {
                  role = "pod"
                  namespaces = {
                    names = var.scrape_namespaces
                  }
                }
              ]
              relabel_configs = [
                {
                  source_labels = ["__meta_kubernetes_pod_annotation_prometheus_io_scrape"]
                  action        = "keep"
                  regex         = "true"
                },
                {
                  source_labels = ["__meta_kubernetes_pod_annotation_prometheus_io_port"]
                  action        = "replace"
                  target_label  = "__address__"
                  regex         = "(.+)"
                  replacement   = "$${1}:$${2}"
                }
              ]
            }
          ]
        }
      }

      # -- Grafana configuration
      grafana = {
        enabled = true

        adminPassword = var.grafana_admin_password

        persistence = {
          enabled          = true
          storageClassName = var.storage_class
          size             = var.grafana_storage_size
          accessModes      = ["ReadWriteOnce"]
        }

        resources = {
          requests = {
            cpu    = var.grafana_cpu_request
            memory = var.grafana_memory_request
          }
          limits = {
            cpu    = var.grafana_cpu_limit
            memory = var.grafana_memory_limit
          }
        }

        service = {
          type = "ClusterIP"
        }

        # Grafana ingress (optional)
        ingress = {
          enabled = var.grafana_ingress_enabled
          ingressClassName = var.grafana_ingress_class_name
          hosts   = var.grafana_ingress_enabled ? [var.grafana_ingress_hostname] : []
          tls = var.grafana_ingress_tls_secret_name != "" ? [
            {
              secretName = var.grafana_ingress_tls_secret_name
              hosts      = [var.grafana_ingress_hostname]
            }
          ] : []
        }

        # Loki datasource (added when Loki is enabled)
        additionalDataSources = var.enable_loki ? [
          {
            name      = "Loki"
            type      = "loki"
            url       = "http://${var.loki_release_name}.${var.namespace}.svc.cluster.local:3100"
            access    = "proxy"
            isDefault = false
          }
        ] : []

        nodeSelector = var.node_selector
        tolerations  = var.tolerations
      }

      # -- Alertmanager configuration
      alertmanager = {
        enabled = true

        alertmanagerSpec = {
          resources = {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }

          nodeSelector = var.node_selector
          tolerations  = var.tolerations
        }

        config = var.alert_slack_webhook_url != "" ? {
          global = {
            resolve_timeout = "5m"
          }
          route = {
            group_by        = ["alertname", "namespace"]
            group_wait      = "30s"
            group_interval  = "5m"
            repeat_interval = "4h"
            receiver        = "slack"
            routes = [
              {
                match = {
                  severity = "critical"
                }
                receiver        = "slack"
                repeat_interval = "1h"
              }
            ]
          }
          receivers = [
            {
              name = "slack"
              slack_configs = [
                {
                  api_url    = var.alert_slack_webhook_url
                  channel    = var.alert_slack_channel
                  send_resolved = true
                  title      = "[{{ .Status | toUpper }}] {{ .CommonLabels.alertname }}"
                  text       = "{{ range .Alerts }}*Alert:* {{ .Annotations.summary }}\n*Description:* {{ .Annotations.description }}\n*Namespace:* {{ .Labels.namespace }}\n{{ end }}"
                }
              ]
            }
          ]
        } : {}
      }

      # -- Node exporter
      nodeExporter = {
        enabled = var.enable_node_exporter
      }

      # -- kube-state-metrics
      kubeStateMetrics = {
        enabled = true
      }
    })
  ]

  depends_on = [kubernetes_namespace.observability]
}

# ---------------------------------------------------------------------------
# Loki Stack (Loki + Promtail)
# ---------------------------------------------------------------------------

resource "helm_release" "loki_stack" {
  count = var.enable_loki ? 1 : 0

  name             = var.loki_release_name
  namespace        = var.namespace
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "loki-stack"
  version          = var.loki_chart_version
  timeout          = var.helm_timeout
  wait             = true
  atomic           = true
  create_namespace = false

  values = [
    yamlencode({
      loki = {
        enabled = true

        persistence = {
          enabled          = true
          storageClassName = var.storage_class
          size             = var.loki_storage_size
          accessModes      = ["ReadWriteOnce"]
        }

        config = {
          limits_config = {
            retention_period = "${var.retention_days * 24}h"
          }
          compactor = {
            retention_enabled = true
          }
        }

        resources = {
          requests = {
            cpu    = var.loki_cpu_request
            memory = var.loki_memory_request
          }
          limits = {
            cpu    = var.loki_cpu_limit
            memory = var.loki_memory_limit
          }
        }

        nodeSelector = var.node_selector
        tolerations  = var.tolerations
      }

      promtail = {
        enabled = true

        resources = {
          requests = {
            cpu    = "50m"
            memory = "64Mi"
          }
          limits = {
            cpu    = "200m"
            memory = "256Mi"
          }
        }

        tolerations = var.tolerations
      }

      # Disable sub-chart components we get from kube-prometheus-stack
      grafana = {
        enabled = false
      }

      prometheus = {
        enabled = false
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.observability,
    helm_release.kube_prometheus_stack,
  ]
}
