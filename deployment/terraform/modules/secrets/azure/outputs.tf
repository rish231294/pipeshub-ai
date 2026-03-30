###############################################################################
# Secrets Module - Azure Outputs
###############################################################################

output "key_vault_id" {
  description = "ID of the Azure Key Vault"
  value       = azurerm_key_vault.this.id
}

output "key_vault_uri" {
  description = "URI of the Azure Key Vault"
  value       = azurerm_key_vault.this.vault_uri
}

output "key_vault_name" {
  description = "Name of the Azure Key Vault"
  value       = azurerm_key_vault.this.name
}

output "secret_ids" {
  description = "Map of secret names to their Key Vault secret IDs"
  value       = { for k, v in azurerm_key_vault_secret.this : k => v.id }
}

output "eso_identity_client_id" {
  description = "Client ID of the ESO managed identity for workload identity"
  value       = azurerm_user_assigned_identity.eso.client_id
}

output "eso_identity_principal_id" {
  description = "Principal ID of the ESO managed identity"
  value       = azurerm_user_assigned_identity.eso.principal_id
}
