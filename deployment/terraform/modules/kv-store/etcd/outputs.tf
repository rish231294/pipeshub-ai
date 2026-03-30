output "client_endpoint" {
  description = "etcd client endpoint for application connections"
  value       = var.enabled ? "http://${var.release_name}.${var.namespace}.svc.cluster.local:2379" : ""
}

output "service_name" {
  description = "Kubernetes service name for etcd"
  value       = var.enabled ? var.release_name : ""
}

output "enabled" {
  description = "Whether etcd is deployed"
  value       = var.enabled
}

output "namespace" {
  description = "Namespace where etcd is deployed"
  value       = var.enabled ? var.namespace : ""
}

output "client_port" {
  description = "etcd client port"
  value       = 2379
}

output "peer_port" {
  description = "etcd peer communication port"
  value       = 2380
}
