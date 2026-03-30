###############################################################################
# Storage Module - Azure Outputs
###############################################################################

output "storage_account_name" {
  description = "Name of the Azure Storage Account"
  value       = azurerm_storage_account.this.name
}

output "storage_account_id" {
  description = "ID of the Azure Storage Account"
  value       = azurerm_storage_account.this.id
}

output "primary_blob_endpoint" {
  description = "Primary blob service endpoint URL"
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "primary_access_key" {
  description = "Primary access key for the Storage Account"
  value       = azurerm_storage_account.this.primary_access_key
  sensitive   = true
}

output "container_name" {
  description = "Name of the blob container for document uploads"
  value       = azurerm_storage_container.documents.name
}

output "primary_connection_string" {
  description = "Primary connection string for the Storage Account"
  value       = azurerm_storage_account.this.primary_connection_string
  sensitive   = true
}

output "private_endpoint_ip" {
  description = "Private IP address of the storage private endpoint (null if not enabled)"
  value       = var.enable_private_endpoint ? azurerm_private_endpoint.storage[0].private_service_connection[0].private_ip_address : null
}
