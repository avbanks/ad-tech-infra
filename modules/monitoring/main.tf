# Global metrics backend for every AKS cluster in the environment:
#   ama-metrics (in each cluster) -> DCE -> DCR -> Azure Monitor Workspace -> Grafana / rule groups
# Clusters join by associating themselves with the DCR (modules/aks-cluster).

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_monitor_workspace" "this" {
  name                = var.workspace_name
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  tags                = var.tags
}

# The DCE and DCR must be in the workspace's region. Clusters in any region send to them.
resource "azurerm_monitor_data_collection_endpoint" "prometheus" {
  name                = "dce-${var.workspace_name}"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  kind                = "Linux"
  tags                = var.tags
}

resource "azurerm_monitor_data_collection_rule" "prometheus" {
  name                        = "dcr-${var.workspace_name}-prometheus"
  resource_group_name         = azurerm_resource_group.this.name
  location                    = var.location
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.prometheus.id
  kind                        = "Linux"
  tags                        = var.tags

  destinations {
    monitor_account {
      monitor_account_id = azurerm_monitor_workspace.this.id
      name               = "MonitoringAccount1"
    }
  }

  data_flow {
    streams      = ["Microsoft-PrometheusMetrics"]
    destinations = ["MonitoringAccount1"]
  }

  data_sources {
    prometheus_forwarder {
      streams = ["Microsoft-PrometheusMetrics"]
      name    = "PrometheusDataSource"
    }
  }
}

# Recording rules that the AKS portal would normally create when the add-on is enabled. The
# built-in Grafana Kubernetes dashboards query these. Rule groups have no cluster_name, so one
# group evaluates for every cluster in the workspace; every aggregation keeps the `cluster` label.
locals {
  rule_groups = {
    for f in fileset("${path.module}/rules", "*.yaml") :
    trimsuffix(f, ".yaml") => yamldecode(file("${path.module}/rules/${f}"))
  }
}

resource "azurerm_monitor_alert_prometheus_rule_group" "recording" {
  for_each = local.rule_groups

  name                = "${each.key}-${var.workspace_name}"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  description         = each.value.description
  rule_group_enabled  = true
  interval            = "PT1M"
  scopes              = [azurerm_monitor_workspace.this.id]
  tags                = var.tags

  dynamic "rule" {
    for_each = each.value.rules
    content {
      enabled    = true
      record     = rule.value.record
      expression = rule.value.expr
      labels     = try(rule.value.labels, null)
    }
  }
}

# ---------------------------------- Grafana ----------------------------------

resource "azurerm_dashboard_grafana" "this" {
  count = var.grafana == null ? 0 : 1

  name                  = var.grafana.name
  resource_group_name   = azurerm_resource_group.this.name
  location              = var.location
  sku                   = var.grafana.sku
  grafana_major_version = var.grafana.major_version
  tags                  = var.tags

  identity {
    type = "SystemAssigned"
  }

  azure_monitor_workspace_integrations {
    resource_id = azurerm_monitor_workspace.this.id
  }
}

# Lets Grafana's managed identity run PromQL against the workspace.
resource "azurerm_role_assignment" "grafana_reads_workspace" {
  count = var.grafana == null ? 0 : 1

  scope                = azurerm_monitor_workspace.this.id
  role_definition_name = "Monitoring Data Reader"
  principal_id         = azurerm_dashboard_grafana.this[0].identity[0].principal_id
}

resource "azurerm_role_assignment" "grafana_admin" {
  count = var.grafana == null ? 0 : 1

  scope                = azurerm_dashboard_grafana.this[0].id
  role_definition_name = "Grafana Admin"
  principal_id         = var.admin_group_object_id
  principal_type       = "Group"
}

# Lets the admin group query the workspace directly (PromQL API / portal), not only via Grafana.
resource "azurerm_role_assignment" "admin_reads_workspace" {
  scope                = azurerm_monitor_workspace.this.id
  role_definition_name = "Monitoring Data Reader"
  principal_id         = var.admin_group_object_id
  principal_type       = "Group"
}
