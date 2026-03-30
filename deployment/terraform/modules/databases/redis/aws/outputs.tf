###############################################################################
# Redis (ElastiCache) Module - AWS Outputs
###############################################################################

output "primary_endpoint" {
  description = "Primary endpoint address for the Redis replication group"
  value       = aws_elasticache_replication_group.main.primary_endpoint_address
}

output "reader_endpoint" {
  description = "Reader endpoint address for the Redis replication group"
  value       = aws_elasticache_replication_group.main.reader_endpoint_address
}

output "port" {
  description = "Port on which Redis accepts connections"
  value       = aws_elasticache_replication_group.main.port
}

output "auth_token_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the Redis auth token"
  value       = aws_secretsmanager_secret.auth_token.arn
}

output "connection_url" {
  description = "Redis connection URL (without auth token)"
  value       = "rediss://${aws_elasticache_replication_group.main.primary_endpoint_address}:${aws_elasticache_replication_group.main.port}"
  sensitive   = true
}

output "replication_group_id" {
  description = "ID of the ElastiCache Redis replication group"
  value       = aws_elasticache_replication_group.main.id
}

output "security_group_id" {
  description = "ID of the security group attached to the Redis cluster"
  value       = aws_security_group.redis.id
}
