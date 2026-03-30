###############################################################################
# DocumentDB Module - AWS Outputs
###############################################################################

output "cluster_endpoint" {
  description = "Primary endpoint of the DocumentDB cluster"
  value       = aws_docdb_cluster.main.endpoint
}

output "reader_endpoint" {
  description = "Reader endpoint of the DocumentDB cluster"
  value       = aws_docdb_cluster.main.reader_endpoint
}

output "port" {
  description = "Port on which DocumentDB accepts connections"
  value       = aws_docdb_cluster.main.port
}

output "connection_string" {
  description = "MongoDB-compatible connection string for DocumentDB"
  value       = "mongodb://${var.master_username}:<password>@${aws_docdb_cluster.main.endpoint}:${aws_docdb_cluster.main.port}/?tls=true&replicaSet=rs0&readPreference=secondaryPreferred&retryWrites=false"
  sensitive   = true
}

output "master_password_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the master password"
  value       = aws_secretsmanager_secret.master_password.arn
}

output "cluster_identifier" {
  description = "Identifier of the DocumentDB cluster"
  value       = aws_docdb_cluster.main.cluster_identifier
}

output "security_group_id" {
  description = "ID of the security group attached to the DocumentDB cluster"
  value       = aws_security_group.docdb.id
}
