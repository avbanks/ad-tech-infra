output "fleet_id" {
  value = azapi_resource.fleet.id
}

output "fleet_name" {
  value = azapi_resource.fleet.name
}

output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "update_strategy_ids" {
  description = "waves = full staged rollout; wave-N = that wave only."
  value = merge(
    { waves = azurerm_kubernetes_fleet_update_strategy.waves.id },
    { for k, v in azurerm_kubernetes_fleet_update_strategy.wave : k => v.id },
  )
}
