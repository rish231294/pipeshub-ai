output "service_name" {
  description = "Kubernetes service name for ArangoDB"
  value       = "${var.release_name}-arangodb"
}

output "port" {
  description = "ArangoDB HTTP port"
  value       = 8529
}

output "internal_url" {
  description = "Internal cluster URL for connecting to ArangoDB"
  value       = "http://${var.release_name}-arangodb.${var.namespace}.svc.cluster.local:8529"
}

output "namespace" {
  description = "Namespace where ArangoDB is deployed"
  value       = var.namespace
}

output "release_name" {
  description = "Helm release name"
  value       = helm_release.arangodb.name
}
