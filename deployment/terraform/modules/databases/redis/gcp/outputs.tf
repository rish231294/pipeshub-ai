###############################################################################
# Redis Module - GCP Outputs
# Exposes Redis connection details for application configuration
###############################################################################

output "host" {
  description = "The IP address of the Redis instance"
  value       = google_redis_instance.main.host
}

output "port" {
  description = "The port number of the Redis instance"
  value       = google_redis_instance.main.port
}

output "auth_string" {
  description = "AUTH string for the Redis instance (empty if AUTH is disabled)"
  value       = google_redis_instance.main.auth_string
  sensitive   = true
}

output "current_location_id" {
  description = "The current zone where the Redis primary node is located"
  value       = google_redis_instance.main.current_location_id
}

output "read_endpoint" {
  description = "Read endpoint IP for HA instances (empty for BASIC tier)"
  value       = var.tier == "STANDARD_HA" ? google_redis_instance.main.read_endpoint : ""
}
