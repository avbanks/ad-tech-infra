resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# azapi is used because azurerm's hub_profile is deprecated and no longer sent to the API.
# The hub is what enables ClusterResourcePlacement (multi-cluster resource propagation).
resource "azapi_resource" "fleet" {
  type      = "Microsoft.ContainerService/fleets@2025-03-01"
  name      = var.name
  parent_id = azurerm_resource_group.this.id
  location  = var.location
  tags      = var.tags

  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {
      hubProfile = {
        dnsPrefix = var.name
        agentProfile = {
          vmSize = var.hub_vm_size
        }
      }
    }
  }

  response_export_values = ["properties.hubProfile.fqdn", "properties.hubProfile.kubernetesVersion"]
}

# Primary region first, bake, then its paired region - never both halves of a pair at once.
resource "azurerm_kubernetes_fleet_update_strategy" "paired_regions" {
  name                        = "paired-regions"
  kubernetes_fleet_manager_id = azapi_resource.fleet.id

  dynamic "stage" {
    for_each = var.update_stages
    content {
      name                        = stage.value.name
      after_stage_wait_in_seconds = stage.value.after_stage_wait_seconds

      dynamic "group" {
        for_each = stage.value.groups
        content {
          name = group.value
        }
      }
    }
  }
}

# Fleet auto-upgrade: when a new version lands in the channel, Fleet starts an update run
# that follows the paired-regions strategy above.
resource "azapi_resource" "auto_upgrade" {
  count = var.auto_upgrade == null ? 0 : 1

  type      = "Microsoft.ContainerService/fleets/autoUpgradeProfiles@2025-03-01"
  name      = "default"
  parent_id = azapi_resource.fleet.id

  body = {
    properties = {
      channel          = var.auto_upgrade.channel
      updateStrategyId = azurerm_kubernetes_fleet_update_strategy.paired_regions.id
      nodeImageSelection = {
        type = "Latest"
      }
    }
  }
}

resource "azurerm_role_assignment" "hub_admin" {
  scope                = azapi_resource.fleet.id
  role_definition_name = "Azure Kubernetes Fleet Manager RBAC Cluster Admin"
  principal_id         = var.admin_group_object_id
  principal_type       = "Group"
}
