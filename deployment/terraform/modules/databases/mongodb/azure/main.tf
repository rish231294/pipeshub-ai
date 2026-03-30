###############################################################################
# MongoDB Module - Azure (Cosmos DB with MongoDB API)
# Creates a Cosmos DB account with MongoDB API, database, collections, and
# private endpoint
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
  account_name = var.account_name != "" ? var.account_name : "${var.project_name}-${var.environment}-cosmos"

  common_tags = merge(var.tags, {
    environment = var.environment
    project     = var.project_name
    managed_by  = "terraform"
    module      = "mongodb"
  })
}

# -----------------------------------------------------------------------------
# Cosmos DB Account (MongoDB API)
# -----------------------------------------------------------------------------

resource "azurerm_cosmosdb_account" "this" {
  name                = local.account_name
  location            = var.location
  resource_group_name = var.resource_group_name
  offer_type          = "Standard"
  kind                = "MongoDB"
  tags                = local.common_tags

  # Free tier is available for dev but limited to one per subscription
  free_tier_enabled = var.environment == "dev"

  # MongoDB server version
  mongo_server_version = "4.2"

  # Capacity mode
  capacity {
    total_throughput_limit = var.capacity_mode == "Serverless" ? -1 : -1
  }

  capabilities {
    name = "EnableMongo"
  }

  dynamic "capabilities" {
    for_each = var.capacity_mode == "Serverless" ? [1] : []
    content {
      name = "EnableServerless"
    }
  }

  # Consistency policy
  consistency_policy {
    consistency_level       = var.consistency_level
    max_interval_in_seconds = var.consistency_level == "BoundedStaleness" ? 300 : null
    max_staleness_prefix    = var.consistency_level == "BoundedStaleness" ? 100000 : null
  }

  # Primary geo-location (always required)
  geo_location {
    location          = var.location
    failover_priority = 0
  }

  # Additional geo-replication locations for prod
  dynamic "geo_location" {
    for_each = var.geo_replication_locations
    content {
      location          = geo_location.value.location
      failover_priority = geo_location.value.failover_priority
    }
  }

  # Networking: restrict to private endpoint only
  public_network_access_enabled     = false
  is_virtual_network_filter_enabled = true

  # Backup policy
  dynamic "backup" {
    for_each = var.environment == "prod" ? [1] : []
    content {
      type                = "Continuous"
      tier                = "Continuous7Days"
      storage_redundancy  = "Geo"
    }
  }

  dynamic "backup" {
    for_each = var.environment != "prod" ? [1] : []
    content {
      type                = "Periodic"
      interval_in_minutes = 1440
      retention_in_hours  = 48
      storage_redundancy  = "Local"
    }
  }

  lifecycle {
    prevent_destroy = false
  }
}

# -----------------------------------------------------------------------------
# MongoDB Database
# -----------------------------------------------------------------------------

resource "azurerm_cosmosdb_mongo_database" "this" {
  name                = var.database_name
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.this.name

  # Autoscale throughput for provisioned mode (applies at database level)
  dynamic "autoscale_settings" {
    for_each = var.capacity_mode == "Provisioned" ? [1] : []
    content {
      max_throughput = var.max_throughput
    }
  }
}

# -----------------------------------------------------------------------------
# MongoDB Collections
# -----------------------------------------------------------------------------

resource "azurerm_cosmosdb_mongo_collection" "this" {
  for_each = var.collections

  name                = each.key
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.this.name
  database_name       = azurerm_cosmosdb_mongo_database.this.name
  shard_key           = each.value.shard_key

  index {
    keys   = ["_id"]
    unique = true
  }

  # Collection-level throughput override (only for provisioned mode)
  dynamic "autoscale_settings" {
    for_each = var.capacity_mode == "Provisioned" && each.value.throughput != null ? [1] : []
    content {
      max_throughput = each.value.throughput
    }
  }
}

# -----------------------------------------------------------------------------
# Private Endpoint
# -----------------------------------------------------------------------------

resource "azurerm_private_endpoint" "cosmos" {
  name                = "${local.account_name}-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.database_subnet_id
  tags                = local.common_tags

  private_service_connection {
    name                           = "${local.account_name}-psc"
    private_connection_resource_id = azurerm_cosmosdb_account.this.id
    is_manual_connection           = false
    subresource_names              = ["MongoDB"]
  }
}

# -----------------------------------------------------------------------------
# Private DNS Zone for Cosmos DB
# -----------------------------------------------------------------------------

resource "azurerm_private_dns_zone" "cosmos" {
  name                = "privatelink.mongo.cosmos.azure.com"
  resource_group_name = var.resource_group_name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "cosmos" {
  name                  = "${local.account_name}-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.cosmos.name
  virtual_network_id    = regex("(.+)/subnets/", var.database_subnet_id)[0]
  registration_enabled  = false
  tags                  = local.common_tags
}

resource "azurerm_private_dns_a_record" "cosmos" {
  name                = local.account_name
  zone_name           = azurerm_private_dns_zone.cosmos.name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = [azurerm_private_endpoint.cosmos.private_service_connection[0].private_ip_address]
  tags                = local.common_tags
}
