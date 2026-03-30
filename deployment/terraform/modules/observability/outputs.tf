output "grafana_service_name" {
  description = "Kubernetes service name for Grafana"
  value       = "${var.prometheus_release_name}-grafana"
}

output "prometheus_service_name" {
  description = "Kubernetes service name for the Prometheus server"
  value       = "${var.prometheus_release_name}-prometheus"
}

output "alertmanager_service_name" {
  description = "Kubernetes service name for Alertmanager"
  value       = "${var.prometheus_release_name}-alertmanager"
}

output "grafana_port" {
  description = "Grafana service port"
  value       = 80
}

output "prometheus_port" {
  description = "Prometheus service port"
  value       = 9090
}

output "grafana_internal_url" {
  description = "Internal cluster URL for Grafana"
  value       = "http://${var.prometheus_release_name}-grafana.${var.namespace}.svc.cluster.local:80"
}

output "prometheus_internal_url" {
  description = "Internal cluster URL for Prometheus"
  value       = "http://${var.prometheus_release_name}-prometheus.${var.namespace}.svc.cluster.local:9090"
}

output "loki_internal_url" {
  description = "Internal cluster URL for Loki (empty when Loki is disabled)"
  value       = var.enable_loki ? "http://${var.loki_release_name}.${var.namespace}.svc.cluster.local:3100" : ""
}

output "namespace" {
  description = "Namespace where the observability stack is deployed"
  value       = var.namespace
}

output "loki_enabled" {
  description = "Whether the Loki log aggregation stack is deployed"
  value       = var.enable_loki
}
