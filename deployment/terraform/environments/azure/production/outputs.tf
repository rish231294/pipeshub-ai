# -----------------------------------------------------------------------------
# PipesHub AI - Azure Environment Outputs
# -----------------------------------------------------------------------------

output "cluster_endpoint" {
  description = "AKS cluster API endpoint"
  value       = module.kubernetes.cluster_endpoint
}

output "cluster_name" {
  description = "AKS cluster name"
  value       = module.kubernetes.cluster_name
}

output "app_url" {
  description = "Application URL"
  value       = "https://${var.domain_name}"
}

output "mongodb_endpoint" {
  description = "Cosmos DB (MongoDB) connection string"
  value       = module.mongodb.connection_string
  sensitive   = true
}

output "redis_endpoint" {
  description = "Azure Cache for Redis hostname"
  value       = module.redis.hostname
}

output "kafka_endpoint" {
  description = "Event Hubs Kafka endpoint"
  value       = module.kafka.kafka_endpoint
}

output "grafana_url" {
  description = "Grafana dashboard URL"
  value       = module.observability.grafana_url
}
