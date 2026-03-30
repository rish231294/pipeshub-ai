###############################################################################
# Storage Module - Azure (Storage Account + Blob Container)
# Creates a Storage Account with blob container, lifecycle rules, CORS,
# private endpoint, and managed identity access for AKS workloads
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

locals {
  # Storage account names: no hyphens, max 24 chars, lowercase alphanumeric only
  storage_account_name = var.storage_account_name != "" ? var.storage_account_name : replace(
    substr("${var.project_name}${var.environment}stor", 0, 24),
    "-", ""
  )

  common_tags = merge(var.tags, {
    environment = var.environment
    project     = var.project_name
    managed_by  = "terraform"
    module      = "storage"
  })
}

# -----------------------------------------------------------------------------
# Azure Storage Account
# -----------------------------------------------------------------------------

resource "azurerm_storage_account" "this" {
  name                          = local.storage_account_name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  account_tier                  = "Standard"
  account_kind                  = "StorageV2"
  account_replication_type      = var.account_replication_type
  access_tier                   = "Hot"
  min_tls_version               = "TLS1_2"
  public_network_access_enabled = !var.enable_private_endpoint
  tags                          = local.common_tags

  blob_properties {
    versioning_enabled       = var.environment == "prod"
    change_feed_enabled      = var.environment == "prod"
    last_access_time_enabled = var.lifecycle_rules_enabled

    # Soft delete for blobs
    delete_retention_policy {
      days = var.environment == "prod" ? 30 : 7
    }

    # Soft delete for containers
    container_delete_retention_policy {
      days = var.environment == "prod" ? 30 : 7
    }

    # CORS rules for frontend access
    dynamic "cors_rule" {
      for_each = length(var.cors_allowed_origins) > 0 ? [1] : []
      content {
        allowed_headers    = ["*"]
        allowed_methods    = ["GET", "HEAD", "PUT", "POST", "DELETE"]
        allowed_origins    = var.cors_allowed_origins
        exposed_headers    = ["Content-Length", "Content-Type", "x-ms-request-id"]
        max_age_in_seconds = 3600
      }
    }
  }

  lifecycle {
    prevent_destroy = false
  }
}

# -----------------------------------------------------------------------------
# Blob Container for Document Uploads
# -----------------------------------------------------------------------------

resource "azurerm_storage_container" "documents" {
  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

# -----------------------------------------------------------------------------
# Lifecycle Management Rules
# -----------------------------------------------------------------------------

resource "azurerm_storage_management_policy" "lifecycle" {
  count = var.lifecycle_rules_enabled ? 1 : 0

  storage_account_id = azurerm_storage_account.this.id

  rule {
    name    = "cool-after-90-days"
    enabled = true

    filters {
      prefix_match = [var.container_name]
      blob_types   = ["blockBlob"]
    }

    actions {
      base_blob {
        tier_to_cool_after_days_since_last_access_time_greater_than = 90
      }
    }
  }

  rule {
    name    = "archive-after-365-days"
    enabled = true

    filters {
      prefix_match = [var.container_name]
      blob_types   = ["blockBlob"]
    }

    actions {
      base_blob {
        tier_to_archive_after_days_since_last_access_time_greater_than = 365
      }
    }
  }

  rule {
    name    = "delete-old-snapshots"
    enabled = true

    filters {
      prefix_match = [var.container_name]
      blob_types   = ["blockBlob"]
    }

    actions {
      snapshot {
        delete_after_days_since_creation_greater_than = 90
      }
    }
  }
}

# -----------------------------------------------------------------------------
# RBAC: Storage Blob Data Contributor for AKS Workload Identity
# -----------------------------------------------------------------------------

resource "azurerm_role_assignment" "aks_blob_contributor" {
  count = var.aks_kubelet_identity_object_id != "" ? 1 : 0

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.aks_kubelet_identity_object_id
}

# -----------------------------------------------------------------------------
# Private Endpoint (optional)
# -----------------------------------------------------------------------------

resource "azurerm_private_endpoint" "storage" {
  count = var.enable_private_endpoint ? 1 : 0

  name                = "${local.storage_account_name}-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.database_subnet_id
  tags                = local.common_tags

  private_service_connection {
    name                           = "${local.storage_account_name}-psc"
    private_connection_resource_id = azurerm_storage_account.this.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }
}

# -----------------------------------------------------------------------------
# Private DNS Zone for Blob Storage
# -----------------------------------------------------------------------------

resource "azurerm_private_dns_zone" "blob" {
  count = var.enable_private_endpoint ? 1 : 0

  name                = "privatelink.blob.core.windows.net"
  resource_group_name = var.resource_group_name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  count = var.enable_private_endpoint ? 1 : 0

  name                  = "${local.storage_account_name}-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.blob[0].name
  virtual_network_id    = regex("(.+)/subnets/", var.database_subnet_id)[0]
  registration_enabled  = false
  tags                  = local.common_tags
}

resource "azurerm_private_dns_a_record" "blob" {
  count = var.enable_private_endpoint ? 1 : 0

  name                = local.storage_account_name
  zone_name           = azurerm_private_dns_zone.blob[0].name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = [azurerm_private_endpoint.storage[0].private_service_connection[0].private_ip_address]
  tags                = local.common_tags
}
