output "release_name" {
  description = "Helm release name of the PipesHub AI deployment"
  value       = helm_release.pipeshub_ai.name
}

output "namespace" {
  description = "Kubernetes namespace where PipesHub AI is deployed"
  value       = var.namespace
}

output "service_endpoints" {
  description = "Map of PipesHub AI service endpoints within the cluster"
  value = {
    frontend  = "http://${var.release_name}.${var.namespace}.svc.cluster.local:3000"
    connector = "http://${var.release_name}.${var.namespace}.svc.cluster.local:8088"
    indexing  = "http://${var.release_name}.${var.namespace}.svc.cluster.local:8091"
    query     = "http://${var.release_name}.${var.namespace}.svc.cluster.local:8000"
  }
}

output "chart_version" {
  description = "Version of the deployed Helm chart"
  value       = helm_release.pipeshub_ai.version
}

output "app_version" {
  description = "Application version (image tag) of the deployed release"
  value       = var.image_tag
}

output "ingress_enabled" {
  description = "Whether ingress is enabled for the deployment"
  value       = var.ingress_config.enabled
}

output "ingress_hostname" {
  description = "Ingress hostname (empty when ingress is disabled)"
  value       = var.ingress_config.enabled ? var.ingress_config.hostname : ""
}
