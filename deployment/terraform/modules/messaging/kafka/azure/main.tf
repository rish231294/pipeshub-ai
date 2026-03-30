###############################################################################
# Kafka Module - Azure (Event Hubs with Kafka Protocol)
# Creates an Event Hubs namespace with Kafka-compatible topics, consumer
# groups, shared access policies, and private endpoint
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
  namespace_name = var.namespace_name != "" ? var.namespace_name : "${var.project_name}-${var.environment}-eventhubs"

  common_tags = merge(var.tags, {
    environment = var.environment
    project     = var.project_name
    managed_by  = "terraform"
    module      = "kafka"
  })

  # Create a map from topic list for easier iteration
  topics_map = { for t in var.topics : t.name => t }
}

# -----------------------------------------------------------------------------
# Event Hubs Namespace (Kafka-compatible)
# -----------------------------------------------------------------------------

resource "azurerm_eventhub_namespace" "this" {
  name                          = local.namespace_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  sku                           = var.sku
  capacity                      = var.capacity
  public_network_access_enabled = false
  local_authentication_enabled  = true
  tags                          = local.common_tags

  # Auto-inflate for Standard tier to handle traffic spikes
  dynamic "identity" {
    for_each = var.sku == "Premium" ? [1] : []
    content {
      type = "SystemAssigned"
    }
  }

  lifecycle {
    prevent_destroy = false
  }
}

# -----------------------------------------------------------------------------
# Event Hubs (Kafka Topics)
# -----------------------------------------------------------------------------

resource "azurerm_eventhub" "this" {
  for_each = local.topics_map

  name                = each.value.name
  namespace_name      = azurerm_eventhub_namespace.this.name
  resource_group_name = var.resource_group_name
  partition_count     = each.value.partition_count
  message_retention   = each.value.retention_days
}

# -----------------------------------------------------------------------------
# Consumer Groups
# -----------------------------------------------------------------------------

resource "azurerm_eventhub_consumer_group" "this" {
  for_each = var.consumer_groups

  name                = each.key
  namespace_name      = azurerm_eventhub_namespace.this.name
  eventhub_name       = azurerm_eventhub.this[each.value.topic_name].name
  resource_group_name = var.resource_group_name
  user_metadata       = each.value.user_metadata
}

# -----------------------------------------------------------------------------
# Shared Access Policies (Send / Listen)
# -----------------------------------------------------------------------------

resource "azurerm_eventhub_namespace_authorization_rule" "send" {
  name                = "${local.namespace_name}-send"
  namespace_name      = azurerm_eventhub_namespace.this.name
  resource_group_name = var.resource_group_name

  listen = false
  send   = true
  manage = false
}

resource "azurerm_eventhub_namespace_authorization_rule" "listen" {
  name                = "${local.namespace_name}-listen"
  namespace_name      = azurerm_eventhub_namespace.this.name
  resource_group_name = var.resource_group_name

  listen = true
  send   = false
  manage = false
}

# -----------------------------------------------------------------------------
# Private Endpoint
# -----------------------------------------------------------------------------

resource "azurerm_private_endpoint" "eventhubs" {
  name                = "${local.namespace_name}-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.database_subnet_id
  tags                = local.common_tags

  private_service_connection {
    name                           = "${local.namespace_name}-psc"
    private_connection_resource_id = azurerm_eventhub_namespace.this.id
    is_manual_connection           = false
    subresource_names              = ["namespace"]
  }
}

# -----------------------------------------------------------------------------
# Private DNS Zone for Event Hubs
# -----------------------------------------------------------------------------

resource "azurerm_private_dns_zone" "eventhubs" {
  name                = "privatelink.servicebus.windows.net"
  resource_group_name = var.resource_group_name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "eventhubs" {
  name                  = "${local.namespace_name}-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.eventhubs.name
  virtual_network_id    = regex("(.+)/subnets/", var.database_subnet_id)[0]
  registration_enabled  = false
  tags                  = local.common_tags
}

resource "azurerm_private_dns_a_record" "eventhubs" {
  name                = local.namespace_name
  zone_name           = azurerm_private_dns_zone.eventhubs.name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = [azurerm_private_endpoint.eventhubs.private_service_connection[0].private_ip_address]
  tags                = local.common_tags
}
