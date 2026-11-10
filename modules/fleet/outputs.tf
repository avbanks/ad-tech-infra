output "fleet_id" {
  value = azapi_resource.fleet.id
}

output "fleet_name" {
  value = azapi_resource.fleet.name
}

output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "hub_fqdn" {
  value = try(azapi_resource.fleet.output.properties.hubProfile.fqdn, null)
}

output "update_strategy_id" {
  value = azurerm_kubernetes_fleet_update_strategy.paired_regions.id
}
