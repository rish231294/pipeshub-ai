output "bolt_endpoint" {
  description = "Neo4j Bolt protocol endpoint for driver connections"
  value       = var.enabled ? "bolt://${var.release_name}.${var.namespace}.svc.cluster.local:7687" : ""
}

output "http_endpoint" {
  description = "Neo4j HTTP endpoint for browser and REST API access"
  value       = var.enabled ? "http://${var.release_name}.${var.namespace}.svc.cluster.local:7474" : ""
}

output "service_name" {
  description = "Kubernetes service name for Neo4j"
  value       = var.enabled ? var.release_name : ""
}

output "enabled" {
  description = "Whether Neo4j is deployed"
  value       = var.enabled
}

output "namespace" {
  description = "Namespace where Neo4j is deployed"
  value       = var.enabled ? var.namespace : ""
}

output "bolt_port" {
  description = "Neo4j Bolt protocol port"
  value       = 7687
}

output "http_port" {
  description = "Neo4j HTTP port"
  value       = 7474
}
