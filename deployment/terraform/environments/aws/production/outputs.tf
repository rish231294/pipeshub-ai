# -----------------------------------------------------------------------------
# PipesHub AI - AWS Environment Outputs
# -----------------------------------------------------------------------------

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.kubernetes.cluster_endpoint
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.kubernetes.cluster_name
}

output "app_url" {
  description = "Application URL"
  value       = "https://${var.domain_name}"
}

output "mongodb_endpoint" {
  description = "DocumentDB cluster endpoint"
  value       = module.mongodb.connection_string
  sensitive   = true
}

output "redis_endpoint" {
  description = "ElastiCache Redis primary endpoint"
  value       = module.redis.primary_endpoint
}

output "kafka_brokers" {
  description = "MSK bootstrap brokers (TLS)"
  value       = module.kafka.bootstrap_brokers_tls
}

output "grafana_url" {
  description = "Grafana dashboard URL"
  value       = module.observability.grafana_url
}
