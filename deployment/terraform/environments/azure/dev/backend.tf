# -----------------------------------------------------------------------------
# Terraform Backend Configuration - Azure Dev
# State is stored in Azure Storage (created by global/azure bootstrap)
# -----------------------------------------------------------------------------

terraform {
  backend "azurerm" {
    resource_group_name  = "pipeshub-ai-terraform-state"
    storage_account_name = "pipeshubaitfstate"
    container_name       = "tfstate"
    key                  = "dev/terraform.tfstate"
  }
}
