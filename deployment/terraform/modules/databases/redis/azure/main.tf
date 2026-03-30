###############################################################################
# Redis Module - Azure (Azure Cache for Redis)
# Creates an Azure Cache for Redis with private endpoint and TLS enforcement
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
  cache_name = var.cache_name != "" ? var.cache_name : "${var.project_name}-${var.environment}-redis"

  common_tags = merge(var.tags, {
    environment = var.environment
    project     = var.project_name
    managed_by  = "terraform"
    module      = "redis"
  })
}

# -----------------------------------------------------------------------------
# Azure Cache for Redis
# -----------------------------------------------------------------------------

resource "azurerm_redis_cache" "this" {
  name                          = local.cache_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  capacity                      = var.capacity
  family                        = var.family
  sku_name                      = var.sku_name
  non_ssl_port_enabled          = var.enable_non_ssl_port
  minimum_tls_version           = var.minimum_tls_version
  public_network_access_enabled = false
  tags                          = local.common_tags

  redis_configuration {
    maxmemory_policy = var.maxmemory_policy
  }

  # Patching schedule for Standard and Premium tiers
  dynamic "patch_schedule" {
    for_each = var.sku_name != "Basic" ? [1] : []
    content {
      day_of_week    = "Sunday"
      start_hour_utc = 2
    }
  }

  lifecycle {
    prevent_destroy = false
  }
}

# -----------------------------------------------------------------------------
# Private Endpoint
# -----------------------------------------------------------------------------

resource "azurerm_private_endpoint" "redis" {
  name                = "${local.cache_name}-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.database_subnet_id
  tags                = local.common_tags

  private_service_connection {
    name                           = "${local.cache_name}-psc"
    private_connection_resource_id = azurerm_redis_cache.this.id
    is_manual_connection           = false
    subresource_names              = ["redisCache"]
  }
}

# -----------------------------------------------------------------------------
# Private DNS Zone for Redis
# -----------------------------------------------------------------------------

resource "azurerm_private_dns_zone" "redis" {
  name                = "privatelink.redis.cache.windows.net"
  resource_group_name = var.resource_group_name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "redis" {
  name                  = "${local.cache_name}-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.redis.name
  virtual_network_id    = regex("(.+)/subnets/", var.database_subnet_id)[0]
  registration_enabled  = false
  tags                  = local.common_tags
}

resource "azurerm_private_dns_a_record" "redis" {
  name                = local.cache_name
  zone_name           = azurerm_private_dns_zone.redis.name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = [azurerm_private_endpoint.redis.private_service_connection[0].private_ip_address]
  tags                = local.common_tags
}
