# -----------------------------------------------------------------------------
# Global Bootstrap - Azure Outputs
# -----------------------------------------------------------------------------

output "storage_account_name" {
  description = "Name of the Storage Account used for Terraform state"
  value       = azurerm_storage_account.terraform_state.name
}

output "container_name" {
  description = "Name of the Storage Container used for Terraform state"
  value       = azurerm_storage_container.terraform_state.name
}

output "acr_login_server" {
  description = "Login server URL for the Azure Container Registry"
  value       = azurerm_container_registry.pipeshub.login_server
}

output "resource_group_name" {
  description = "Name of the resource group containing bootstrap resources"
  value       = azurerm_resource_group.terraform_state.name
}
