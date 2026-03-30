###############################################################################
# Networking Module - GCP Outputs
# Exposes VPC, subnet, and NAT details for downstream modules
###############################################################################

output "network_id" {
  description = "The unique identifier of the VPC network"
  value       = google_compute_network.vpc.id
}

output "network_name" {
  description = "The name of the VPC network"
  value       = google_compute_network.vpc.name
}

output "network_self_link" {
  description = "The self-link URI of the VPC network"
  value       = google_compute_network.vpc.self_link
}

output "gke_subnet_id" {
  description = "The unique identifier of the GKE subnet"
  value       = google_compute_subnetwork.gke.id
}

output "gke_subnet_name" {
  description = "The name of the GKE subnet"
  value       = google_compute_subnetwork.gke.name
}

output "database_subnet_id" {
  description = "The unique identifier of the database subnet"
  value       = google_compute_subnetwork.database.id
}

output "public_subnet_id" {
  description = "The unique identifier of the public subnet"
  value       = google_compute_subnetwork.public.id
}

output "cloud_nat_ip" {
  description = "The external IP address used by Cloud NAT"
  value       = google_compute_address.nat_ip.address
}

output "pod_secondary_range_name" {
  description = "The name of the secondary IP range for GKE pods"
  value       = google_compute_subnetwork.gke.secondary_ip_range[0].range_name
}

output "service_secondary_range_name" {
  description = "The name of the secondary IP range for GKE services"
  value       = google_compute_subnetwork.gke.secondary_ip_range[1].range_name
}
