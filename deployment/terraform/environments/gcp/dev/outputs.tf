# -----------------------------------------------------------------------------
# PipesHub AI - GCP Environment Outputs
# -----------------------------------------------------------------------------

output "cluster_endpoint" {
  description = "GKE cluster API endpoint"
  value       = module.kubernetes.cluster_endpoint
}

output "cluster_name" {
  description = "GKE cluster name"
  value       = module.kubernetes.cluster_name
}

output "app_url" {
  description = "Application URL"
  value       = "https://${var.domain_name}"
}

output "mongodb_endpoint" {
  description = "MongoDB connection string"
  value       = module.mongodb.connection_string
  sensitive   = true
}

output "redis_endpoint" {
  description = "Cloud Memorystore Redis host"
  value       = module.redis.host
}

output "kafka_brokers" {
  description = "Kafka bootstrap brokers"
  value       = module.kafka.bootstrap_brokers
}

output "grafana_url" {
  description = "Grafana dashboard URL"
  value       = module.observability.grafana_url
}
