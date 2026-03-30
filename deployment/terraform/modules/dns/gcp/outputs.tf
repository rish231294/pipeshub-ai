###############################################################################
# DNS Module - GCP Outputs
# Exposes DNS zone, name servers, and SSL certificate details
###############################################################################

output "zone_name" {
  description = "The name of the Cloud DNS managed zone"
  value       = local.zone_name
}

output "name_servers" {
  description = "Name servers for the DNS zone (only populated when zone is created)"
  value       = var.create_zone ? google_dns_managed_zone.zone[0].name_servers : []
}

output "domain_name" {
  description = "The fully qualified domain name configured"
  value       = var.domain_name
}

output "ssl_certificate_id" {
  description = "The ID of the Google-managed SSL certificate"
  value       = google_compute_managed_ssl_certificate.main.id
}
