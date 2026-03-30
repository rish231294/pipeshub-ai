###############################################################################
# Kafka (MSK) Module - AWS Outputs
###############################################################################

output "bootstrap_brokers_tls" {
  description = "TLS connection string for the MSK cluster brokers"
  value       = aws_msk_cluster.main.bootstrap_brokers_tls
}

output "bootstrap_brokers_sasl_scram" {
  description = "SASL/SCRAM connection string for the MSK cluster brokers"
  value       = aws_msk_cluster.main.bootstrap_brokers_sasl_scram
}

output "zookeeper_connect_string" {
  description = "ZooKeeper connection string for the MSK cluster"
  value       = aws_msk_cluster.main.zookeeper_connect_string
}

output "msk_configuration_arn" {
  description = "ARN of the MSK configuration"
  value       = aws_msk_configuration.main.arn
}

output "sasl_credentials_secret_arn" {
  description = "ARN of the Secrets Manager secret containing SASL/SCRAM credentials"
  value       = aws_secretsmanager_secret.sasl_credentials.arn
}

output "cluster_arn" {
  description = "ARN of the MSK cluster"
  value       = aws_msk_cluster.main.arn
}

output "security_group_id" {
  description = "ID of the security group attached to the MSK cluster"
  value       = aws_security_group.msk.id
}

output "cluster_name" {
  description = "Name of the MSK cluster"
  value       = aws_msk_cluster.main.cluster_name
}
