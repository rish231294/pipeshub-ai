###############################################################################
# MongoDB Module - Azure Outputs
###############################################################################

output "connection_string" {
  description = "Primary MongoDB connection string for the Cosmos DB account"
  value       = azurerm_cosmosdb_account.this.primary_mongodb_connection_string
  sensitive   = true
}

output "primary_key" {
  description = "Primary key for the Cosmos DB account"
  value       = azurerm_cosmosdb_account.this.primary_key
  sensitive   = true
}

output "account_endpoint" {
  description = "Endpoint URL of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.this.endpoint
}

output "account_id" {
  description = "ID of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.this.id
}

output "database_name" {
  description = "Name of the MongoDB database"
  value       = azurerm_cosmosdb_mongo_database.this.name
}

output "private_endpoint_ip" {
  description = "Private IP address of the Cosmos DB private endpoint"
  value       = azurerm_private_endpoint.cosmos.private_service_connection[0].private_ip_address
}
