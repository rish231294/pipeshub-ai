variable "namespace" {
  description = "Kubernetes namespace for the observability stack"
  type        = string
  default     = "observability"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.namespace))
    error_message = "Namespace must consist of lowercase alphanumeric characters or hyphens."
  }
}

variable "create_namespace" {
  description = "Whether to create the Kubernetes namespace"
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Prometheus / kube-prometheus-stack
# ---------------------------------------------------------------------------

variable "prometheus_release_name" {
  description = "Helm release name for kube-prometheus-stack"
  type        = string
  default     = "kube-prometheus-stack"
}

variable "prometheus_chart_version" {
  description = "Version of the kube-prometheus-stack Helm chart"
  type        = string
  default     = null
}

variable "prometheus_storage_size" {
  description = "Persistent volume size for Prometheus TSDB"
  type        = string
  default     = "50Gi"

  validation {
    condition     = can(regex("^[0-9]+[KMGT]i$", var.prometheus_storage_size))
    error_message = "Storage size must be a valid Kubernetes quantity (e.g., 50Gi)."
  }
}

variable "prometheus_retention_size" {
  description = "Maximum TSDB size before oldest data is pruned (e.g., 45GB)"
  type        = string
  default     = ""
}

variable "prometheus_cpu_request" {
  description = "CPU request for the Prometheus server"
  type        = string
  default     = "250m"
}

variable "prometheus_cpu_limit" {
  description = "CPU limit for the Prometheus server"
  type        = string
  default     = "1"
}

variable "prometheus_memory_request" {
  description = "Memory request for the Prometheus server"
  type        = string
  default     = "512Mi"
}

variable "prometheus_memory_limit" {
  description = "Memory limit for the Prometheus server"
  type        = string
  default     = "2Gi"
}

variable "retention_days" {
  description = "Number of days to retain metrics and log data"
  type        = number
  default     = 15

  validation {
    condition     = var.retention_days >= 1 && var.retention_days <= 365
    error_message = "Retention days must be between 1 and 365."
  }
}

variable "scrape_namespaces" {
  description = "List of Kubernetes namespaces to scrape for metrics"
  type        = list(string)
  default     = ["pipeshub"]
}

variable "enable_node_exporter" {
  description = "Whether to deploy the Prometheus node exporter DaemonSet"
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Grafana
# ---------------------------------------------------------------------------

variable "grafana_admin_password" {
  description = "Admin password for the Grafana web UI"
  type        = string
  sensitive   = true
}

variable "grafana_storage_size" {
  description = "Persistent volume size for Grafana dashboards and config"
  type        = string
  default     = "10Gi"

  validation {
    condition     = can(regex("^[0-9]+[KMGT]i$", var.grafana_storage_size))
    error_message = "Storage size must be a valid Kubernetes quantity (e.g., 10Gi)."
  }
}

variable "grafana_cpu_request" {
  description = "CPU request for Grafana"
  type        = string
  default     = "100m"
}

variable "grafana_cpu_limit" {
  description = "CPU limit for Grafana"
  type        = string
  default     = "500m"
}

variable "grafana_memory_request" {
  description = "Memory request for Grafana"
  type        = string
  default     = "128Mi"
}

variable "grafana_memory_limit" {
  description = "Memory limit for Grafana"
  type        = string
  default     = "512Mi"
}

variable "grafana_ingress_enabled" {
  description = "Whether to create an Ingress for Grafana"
  type        = bool
  default     = false
}

variable "grafana_ingress_class_name" {
  description = "Ingress class name for Grafana (e.g., nginx, alb)"
  type        = string
  default     = ""
}

variable "grafana_ingress_hostname" {
  description = "Hostname for Grafana ingress"
  type        = string
  default     = ""
}

variable "grafana_ingress_tls_secret_name" {
  description = "TLS secret name for Grafana ingress (empty disables TLS)"
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Alerting
# ---------------------------------------------------------------------------

variable "alert_slack_webhook_url" {
  description = "Slack webhook URL for Alertmanager notifications (empty disables Slack alerts)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "alert_slack_channel" {
  description = "Slack channel for alert notifications"
  type        = string
  default     = "#alerts"
}

# ---------------------------------------------------------------------------
# Loki
# ---------------------------------------------------------------------------

variable "enable_loki" {
  description = "Whether to deploy the Loki log aggregation stack (Loki + Promtail)"
  type        = bool
  default     = true
}

variable "loki_release_name" {
  description = "Helm release name for the Loki stack"
  type        = string
  default     = "loki-stack"
}

variable "loki_chart_version" {
  description = "Version of the Loki-stack Helm chart"
  type        = string
  default     = null
}

variable "loki_storage_size" {
  description = "Persistent volume size for Loki log storage"
  type        = string
  default     = "50Gi"

  validation {
    condition     = can(regex("^[0-9]+[KMGT]i$", var.loki_storage_size))
    error_message = "Storage size must be a valid Kubernetes quantity (e.g., 50Gi)."
  }
}

variable "loki_cpu_request" {
  description = "CPU request for Loki"
  type        = string
  default     = "100m"
}

variable "loki_cpu_limit" {
  description = "CPU limit for Loki"
  type        = string
  default     = "500m"
}

variable "loki_memory_request" {
  description = "Memory request for Loki"
  type        = string
  default     = "256Mi"
}

variable "loki_memory_limit" {
  description = "Memory limit for Loki"
  type        = string
  default     = "1Gi"
}

# ---------------------------------------------------------------------------
# Common
# ---------------------------------------------------------------------------

variable "storage_class" {
  description = "Kubernetes StorageClass for all persistent volumes (empty string uses cluster default)"
  type        = string
  default     = ""
}

variable "labels" {
  description = "Additional labels to apply to all observability resources"
  type        = map(string)
  default     = {}
}

variable "node_selector" {
  description = "Node selector for observability pod scheduling"
  type        = map(string)
  default     = {}
}

variable "tolerations" {
  description = "Tolerations for observability pod scheduling"
  type = list(object({
    key      = string
    operator = string
    value    = optional(string)
    effect   = string
  }))
  default = []
}

variable "helm_timeout" {
  description = "Timeout in seconds for Helm operations"
  type        = number
  default     = 900
}
