resource "azurerm_kubernetes_cluster" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.name
  node_resource_group = "${var.resource_group_name}-${var.name}-nodes"
  kubernetes_version  = var.kubernetes_version
  sku_tier            = var.sku_tier

  # Fleet Manager orchestrates Kubernetes upgrades across the fleet (paired-region strategy),
  # so per-cluster auto-upgrade stays off. Node OS images still self-patch.
  automatic_upgrade_channel = null
  node_os_upgrade_channel   = "NodeImage"

  oidc_issuer_enabled       = true
  workload_identity_enabled = true
  local_account_disabled    = true

  azure_active_directory_role_based_access_control {
    tenant_id              = var.tenant_id
    azure_rbac_enabled     = true
    admin_group_object_ids = var.admin_group_object_ids
  }

  identity {
    type = "SystemAssigned"
  }

  default_node_pool {
    name                         = "system"
    vm_size                      = var.system_vm_size
    node_count                   = var.system_node_count
    vnet_subnet_id               = var.subnet_id
    os_sku                       = "AzureLinux"
    only_critical_addons_enabled = true
    temporary_name_for_rotation  = "systemtmp"

    upgrade_settings {
      max_surge = "10%"
    }
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
    pod_cidr            = var.network.pod_cidr
    service_cidr        = var.network.service_cidr
    dns_service_ip      = var.network.dns_service_ip
  }

  # Azure Managed Prometheus agent (ama-metrics). Where it sends is decided by the DCR association below.
  dynamic "monitor_metrics" {
    for_each = var.prometheus_dcr_id == null ? [] : [1]
    content {}
  }

  tags = var.tags

  lifecycle {
    # Upgrades are driven by Fleet update runs, not by this module.
    ignore_changes = [kubernetes_version]
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "app" {
  name                        = var.app_pool.name
  kubernetes_cluster_id       = azurerm_kubernetes_cluster.this.id
  vm_size                     = var.app_pool.vm_size
  vnet_subnet_id              = var.subnet_id
  mode                        = "User"
  os_sku                      = "AzureLinux"
  auto_scaling_enabled        = true
  min_count                   = var.app_pool.min_count
  max_count                   = var.app_pool.max_count
  temporary_name_for_rotation = "${substr(var.app_pool.name, 0, 9)}tmp"
  node_labels                 = merge({ "adtech.io/role" = var.app_pool.name }, var.app_pool.labels)
  tags                        = var.tags

  upgrade_settings {
    max_surge = "10%"
  }

  lifecycle {
    ignore_changes = [node_count, orchestrator_version]
  }
}

# BYO subnet: the cluster identity must manage internal load balancers / NICs in it.
resource "azurerm_role_assignment" "subnet_network_contributor" {
  scope                = var.subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.this.identity[0].principal_id
}

resource "azurerm_kubernetes_fleet_member" "this" {
  name                  = var.name
  kubernetes_fleet_id   = var.fleet_id
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  group                 = var.fleet_update_group

  depends_on = [azurerm_kubernetes_cluster_node_pool.app]
}

# Points this cluster's ama-metrics agent at the shared DCR -> global Azure Monitor Workspace.
resource "azurerm_monitor_data_collection_rule_association" "prometheus" {
  count = var.prometheus_dcr_id == null ? 0 : 1

  name                    = "prometheus-${var.name}"
  target_resource_id      = azurerm_kubernetes_cluster.this.id
  data_collection_rule_id = var.prometheus_dcr_id
}
