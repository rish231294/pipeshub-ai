###############################################################################
# MongoDB Atlas Module - GCP Outputs
# Exposes connection strings and cluster details
###############################################################################

output "connection_string_srv" {
  description = "SRV connection string for the MongoDB Atlas cluster"
  value       = mongodbatlas_cluster.main.connection_strings[0].standard_srv
  sensitive   = true
}

output "connection_string_standard" {
  description = "Standard connection string for the MongoDB Atlas cluster"
  value       = mongodbatlas_cluster.main.connection_strings[0].standard
  sensitive   = true
}

output "cluster_id" {
  description = "The unique identifier of the MongoDB Atlas cluster"
  value       = mongodbatlas_cluster.main.cluster_id
}
