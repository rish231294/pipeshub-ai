###############################################################################
# Secrets Module - Azure (Key Vault + External Secrets Operator)
# Creates an Azure Key Vault, stores secrets, configures workload identity,
# and installs External Secrets Operator for Kubernetes secret sync
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.25.0"
    }
  }
}

data "azurerm_client_config" "current" {}

locals {
  key_vault_name = var.key_vault_name != "" ? var.key_vault_name : "${var.project_name}-${var.environment}-kv"

  common_tags = merge(var.tags, {
    environment = var.environment
    project     = var.project_name
    managed_by  = "terraform"
    module      = "secrets"
  })
}

# -----------------------------------------------------------------------------
# Azure Key Vault
# -----------------------------------------------------------------------------

resource "azurerm_key_vault" "this" {
  name                          = local.key_vault_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  tenant_id                     = var.tenant_id
  sku_name                      = "standard"
  soft_delete_retention_days    = 7
  purge_protection_enabled      = var.environment == "prod"
  public_network_access_enabled = false
  tags                          = local.common_tags

  enable_rbac_authorization = false

  network_acls {
    bypass         = "AzureServices"
    default_action = "Deny"
  }
}

# -----------------------------------------------------------------------------
# Access Policies
# -----------------------------------------------------------------------------

# Access policy for the Terraform service principal (for managing secrets)
resource "azurerm_key_vault_access_policy" "terraform" {
  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = var.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = [
    "Get",
    "List",
    "Set",
    "Delete",
    "Purge",
    "Recover",
  ]
}

# Access policy for AKS kubelet identity
resource "azurerm_key_vault_access_policy" "aks" {
  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = var.tenant_id
  object_id    = var.aks_kubelet_identity_object_id

  secret_permissions = [
    "Get",
    "List",
  ]
}

# Access policy for ESO managed identity
resource "azurerm_key_vault_access_policy" "eso" {
  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = var.tenant_id
  object_id    = azurerm_user_assigned_identity.eso.principal_id

  secret_permissions = [
    "Get",
    "List",
  ]
}

# -----------------------------------------------------------------------------
# Secrets
# -----------------------------------------------------------------------------

resource "azurerm_key_vault_secret" "this" {
  for_each = var.secrets_map

  name         = each.key
  value        = each.value
  key_vault_id = azurerm_key_vault.this.id
  tags         = local.common_tags

  depends_on = [azurerm_key_vault_access_policy.terraform]
}

# -----------------------------------------------------------------------------
# Managed Identity for External Secrets Operator (Workload Identity)
# -----------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "eso" {
  name                = "${var.project_name}-${var.environment}-eso-identity"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.common_tags
}

resource "azurerm_federated_identity_credential" "eso" {
  name                = "${var.project_name}-${var.environment}-eso-federated"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.eso.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.oidc_issuer_url
  subject             = "system:serviceaccount:${var.eso_namespace}:${var.eso_service_account_name}"
}

# -----------------------------------------------------------------------------
# External Secrets Operator - Helm Release
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "eso" {
  metadata {
    name = var.eso_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "secrets"
    }
  }
}

resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  namespace  = var.eso_namespace
  version    = "0.9.13"
  wait       = true
  timeout    = 300

  set {
    name  = "installCRDs"
    value = "true"
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = var.eso_service_account_name
  }

  set {
    name  = "serviceAccount.annotations.azure\\.workload\\.identity/client-id"
    value = azurerm_user_assigned_identity.eso.client_id
  }

  set {
    name  = "podLabels.azure\\.workload\\.identity/use"
    value = "true"
  }

  depends_on = [
    kubernetes_namespace.eso,
    azurerm_federated_identity_credential.eso,
  ]
}
