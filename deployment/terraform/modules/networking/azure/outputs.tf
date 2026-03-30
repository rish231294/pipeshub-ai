###############################################################################
# Networking Module - Azure Outputs
###############################################################################

output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.this.name
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.this.id
}

output "vnet_id" {
  description = "ID of the Virtual Network"
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "Name of the Virtual Network"
  value       = azurerm_virtual_network.this.name
}

output "aks_subnet_id" {
  description = "ID of the AKS subnet"
  value       = azurerm_subnet.aks.id
}

output "database_subnet_id" {
  description = "ID of the database subnet"
  value       = azurerm_subnet.database.id
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = azurerm_subnet.public.id
}

output "nsg_ids" {
  description = "Map of NSG names to their IDs"
  value = {
    aks      = azurerm_network_security_group.aks.id
    database = azurerm_network_security_group.database.id
    public   = azurerm_network_security_group.public.id
  }
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway (null if not enabled)"
  value       = var.enable_nat_gateway ? azurerm_nat_gateway.this[0].id : null
}

output "nat_public_ip" {
  description = "Public IP address of the NAT Gateway (null if not enabled)"
  value       = var.enable_nat_gateway ? azurerm_public_ip.nat[0].ip_address : null
}
