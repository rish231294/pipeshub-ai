output "http_endpoint" {
  description = "Qdrant HTTP REST API endpoint"
  value       = "http://${var.release_name}.${var.namespace}.svc.cluster.local:6333"
}

output "grpc_endpoint" {
  description = "Qdrant gRPC endpoint for high-performance operations"
  value       = "${var.release_name}.${var.namespace}.svc.cluster.local:6334"
}

output "service_name" {
  description = "Kubernetes service name for Qdrant"
  value       = var.release_name
}

output "http_port" {
  description = "Qdrant HTTP REST API port"
  value       = 6333
}

output "grpc_port" {
  description = "Qdrant gRPC port"
  value       = 6334
}

output "namespace" {
  description = "Namespace where Qdrant is deployed"
  value       = var.namespace
}

output "release_name" {
  description = "Helm release name"
  value       = helm_release.qdrant.name
}
