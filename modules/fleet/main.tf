resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Hubless fleet: an Azure-side grouping of member clusters used only for update orchestration (Kubernetes
# and node-image upgrades in waves). No hub cluster = no VM, no control plane, nothing to patch.
# Workload delivery to members is Flux (k8s/base, k8s/waves), so ClusterResourcePlacement isn't needed.
# azapi because azurerm's fleet resource still models the deprecated hub_profile.
resource "azapi_resource" "fleet" {
  type      = "Microsoft.ContainerService/fleets@2025-03-01"
  name      = var.name
  parent_id = azurerm_resource_group.this.id
  location  = var.location
  tags      = var.tags

  body = {
    properties = {}
  }
}

# Full rollout: wave-1 -> bake -> wave-2 -> bake -> wave-3 (same waves Flux uses for app releases).
resource "azurerm_kubernetes_fleet_update_strategy" "waves" {
  name                        = "waves"
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

# One wave at a time: a single-stage strategy per wave. scripts/fleet-upgrade.sh -w wave-2 uses "wave-2".
# The gate between waves is a human starting the next run.
resource "azurerm_kubernetes_fleet_update_strategy" "wave" {
  for_each = { for s in var.update_stages : s.name => s }

  name                        = each.key
  kubernetes_fleet_manager_id = azapi_resource.fleet.id

  stage {
    name = each.key

    dynamic "group" {
      for_each = each.value.groups
      content {
        name = group.value
      }
    }
  }
}

# Optional. Off in dev: a new version in the channel would start the whole "waves" run on its own.
resource "azapi_resource" "auto_upgrade" {
  count = var.auto_upgrade == null ? 0 : 1

  type      = "Microsoft.ContainerService/fleets/autoUpgradeProfiles@2025-03-01"
  name      = "default"
  parent_id = azapi_resource.fleet.id

  body = {
    properties = {
      channel          = var.auto_upgrade.channel
      updateStrategyId = azurerm_kubernetes_fleet_update_strategy.waves.id
      nodeImageSelection = {
        type = "Latest"
      }
    }
  }
}
