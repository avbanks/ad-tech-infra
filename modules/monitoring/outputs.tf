output "workspace_id" {
  value = azurerm_monitor_workspace.this.id
}

output "query_endpoint" {
  description = "Prometheus-compatible query endpoint (Entra auth)."
  value       = azurerm_monitor_workspace.this.query_endpoint
}

output "data_collection_rule_id" {
  description = "Clusters associate with this DCR to send metrics to the workspace."
  value       = azurerm_monitor_data_collection_rule.prometheus.id
}

output "data_collection_endpoint_id" {
  value = azurerm_monitor_data_collection_endpoint.prometheus.id
}

output "grafana_endpoint" {
  value = try(azurerm_dashboard_grafana.this[0].endpoint, null)
}
