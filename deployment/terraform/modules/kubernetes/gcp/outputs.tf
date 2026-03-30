###############################################################################
# Kubernetes Module - GCP Outputs
# Exposes GKE cluster details, endpoints, and service accounts
###############################################################################

output "cluster_id" {
  description = "The unique identifier of the GKE cluster"
  value       = google_container_cluster.primary.id
}

output "cluster_name" {
  description = "The name of the GKE cluster"
  value       = google_container_cluster.primary.name
}

output "cluster_endpoint" {
  description = "The IP address of the GKE cluster master endpoint"
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64-encoded public certificate authority of the GKE cluster"
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "workload_identity_pool" {
  description = "Workload Identity pool for the GKE cluster (PROJECT_ID.svc.id.goog)"
  value       = google_container_cluster.primary.workload_identity_config[0].workload_pool
}

output "node_pool_service_accounts" {
  description = "Map of node pool names to their GCP service account emails"
  value = {
    for name, sa in google_service_account.node_pool : name => sa.email
  }
}
