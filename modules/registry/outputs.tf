output "id" {
  value = azurerm_container_registry.this.id
}

output "login_server" {
  description = "e.g. acradtechdev.azurecr.io - the CHART_REGISTRY value Flux substitutes into HelmRepository URLs."
  value       = azurerm_container_registry.this.login_server
}
