output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "resource_group_id" {
  value = azurerm_resource_group.this.id
}

output "vnet_id" {
  value = azurerm_virtual_network.this.id
}

output "subnet_ids" {
  description = "Cluster key (e.g. kafka-01) => subnet ID."
  value       = { for k, s in azurerm_subnet.cluster : k => s.id }
}

output "subnet_cidrs" {
  value = { for k, s in azurerm_subnet.cluster : k => s.address_prefixes[0] }
}
