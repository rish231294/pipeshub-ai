###############################################################################
# Redis Module - Azure Outputs
###############################################################################

output "hostname" {
  description = "Hostname of the Azure Cache for Redis instance"
  value       = azurerm_redis_cache.this.hostname
}

output "ssl_port" {
  description = "SSL port of the Azure Cache for Redis instance"
  value       = azurerm_redis_cache.this.ssl_port
}

output "primary_access_key" {
  description = "Primary access key for the Redis cache"
  value       = azurerm_redis_cache.this.primary_access_key
  sensitive   = true
}

output "connection_string" {
  description = "Primary connection string for the Redis cache"
  value       = azurerm_redis_cache.this.primary_connection_string
  sensitive   = true
}

output "redis_url" {
  description = "Redis URL in the format rediss://:<key>@<host>:<port> for application configuration"
  value       = "rediss://:${azurerm_redis_cache.this.primary_access_key}@${azurerm_redis_cache.this.hostname}:${azurerm_redis_cache.this.ssl_port}"
  sensitive   = true
}

output "redis_id" {
  description = "ID of the Azure Cache for Redis instance"
  value       = azurerm_redis_cache.this.id
}

output "private_endpoint_ip" {
  description = "Private IP address of the Redis private endpoint"
  value       = azurerm_private_endpoint.redis.private_service_connection[0].private_ip_address
}
