# -----------------------------------------------------------------------------
# Global Bootstrap - Azure
# Creates shared resources needed before any environment can be provisioned.
# Run once manually with local state: terraform init && terraform apply
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# -----------------------------------------------------------------------------
# Resource Group for Terraform State
# -----------------------------------------------------------------------------

resource "azurerm_resource_group" "terraform_state" {
  name     = "${var.project_name}-terraform-state"
  location = var.location
  tags     = var.tags
}

# -----------------------------------------------------------------------------
# Storage Account for Terraform State
# -----------------------------------------------------------------------------

resource "azurerm_storage_account" "terraform_state" {
  name                     = replace("${var.project_name}tfstate", "-", "")
  resource_group_name      = azurerm_resource_group.terraform_state.name
  location                 = azurerm_resource_group.terraform_state.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Storage Container for State Files
# -----------------------------------------------------------------------------

resource "azurerm_storage_container" "terraform_state" {
  name                  = "tfstate"
  storage_account_name  = azurerm_storage_account.terraform_state.name
  container_access_type = "private"
}

# -----------------------------------------------------------------------------
# Azure Container Registry
# -----------------------------------------------------------------------------

resource "azurerm_container_registry" "pipeshub" {
  name                = replace("${var.project_name}acr", "-", "")
  resource_group_name = azurerm_resource_group.terraform_state.name
  location            = azurerm_resource_group.terraform_state.location
  sku                 = "Basic"
  admin_enabled       = false

  tags = var.tags
}
