# Chart registry for the environment. scripts/publish-charts.sh pushes k8s/charts/* here as OCI Helm
# charts; every cluster's Flux HelmRepository "adtech" pulls from it with the node's managed identity.

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_container_registry" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = var.sku
  admin_enabled       = false
  tags                = var.tags
}

resource "azurerm_role_assignment" "push" {
  for_each = toset(var.pusher_object_ids)

  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPush"
  principal_id         = each.value
}
