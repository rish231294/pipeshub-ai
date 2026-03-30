###############################################################################
# Kafka Module - Azure Outputs
###############################################################################

output "namespace_connection_string" {
  description = "Primary connection string for the Event Hubs namespace"
  value       = azurerm_eventhub_namespace.this.default_primary_connection_string
  sensitive   = true
}

output "kafka_endpoint" {
  description = "Kafka-compatible endpoint for the Event Hubs namespace (use as bootstrap.servers)"
  value       = "${azurerm_eventhub_namespace.this.name}.servicebus.windows.net:9093"
}

output "event_hub_ids" {
  description = "Map of Event Hub (topic) names to their IDs"
  value       = { for k, v in azurerm_eventhub.this : k => v.id }
}

output "send_policy_primary_key" {
  description = "Primary key for the send-only shared access policy"
  value       = azurerm_eventhub_namespace_authorization_rule.send.primary_key
  sensitive   = true
}

output "listen_policy_primary_key" {
  description = "Primary key for the listen-only shared access policy"
  value       = azurerm_eventhub_namespace_authorization_rule.listen.primary_key
  sensitive   = true
}

output "namespace_id" {
  description = "ID of the Event Hubs namespace"
  value       = azurerm_eventhub_namespace.this.id
}

output "send_policy_connection_string" {
  description = "Connection string for the send-only shared access policy"
  value       = azurerm_eventhub_namespace_authorization_rule.send.primary_connection_string
  sensitive   = true
}

output "listen_policy_connection_string" {
  description = "Connection string for the listen-only shared access policy"
  value       = azurerm_eventhub_namespace_authorization_rule.listen.primary_connection_string
  sensitive   = true
}
