###############################################################################
# Kafka Module - GCP Outputs
# Exposes Kafka bootstrap servers and authentication details
###############################################################################

output "bootstrap_servers" {
  description = "Kafka bootstrap servers for plaintext SASL connections"
  value       = "${var.project_name}-${var.environment}-kafka-bootstrap.${var.namespace}.svc.cluster.local:9092"
}

output "bootstrap_servers_tls" {
  description = "Kafka bootstrap servers for TLS SASL connections"
  value       = "${var.project_name}-${var.environment}-kafka-bootstrap.${var.namespace}.svc.cluster.local:9093"
}

output "kafka_user_secret_name" {
  description = "Name of the Kubernetes secret containing SCRAM credentials for the Kafka user"
  value       = "${var.project_name}-${var.environment}-app"
}
