# Standalone single-node AKS cluster for Kubernetes troubleshooting practice.
# Deliberately NOT a Fleet member and in its own RG/VNet/state, so anything broken here can't reach
# the ad-tech cells, the fleet's CRPs or its update runs. Safe to destroy and recreate at will.

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.name_prefix}"
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.name_prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.address_space]
  tags                = var.tags
}

resource "azurerm_subnet" "nodes" {
  name                 = "snet-nodes"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [cidrsubnet(var.address_space, 8, 1)]
}

resource "azurerm_network_security_group" "nodes" {
  name                = "nsg-${var.name_prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "nodes" {
  subnet_id                 = azurerm_subnet.nodes.id
  network_security_group_id = azurerm_network_security_group.nodes.id
}

resource "azurerm_kubernetes_cluster" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  dns_prefix          = var.name
  node_resource_group = "${azurerm_resource_group.this.name}-nodes"
  kubernetes_version  = var.kubernetes_version
  sku_tier            = "Free"

  # Not in a fleet, so the cluster patches itself.
  automatic_upgrade_channel = "patch"
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

  # With an app pool, the system pool is tainted CriticalAddonsOnly and only runs AKS add-ons.
  # Without one, it runs your workloads too.
  default_node_pool {
    name                         = "system"
    vm_size                      = var.vm_size
    node_count                   = var.node_count
    vnet_subnet_id               = azurerm_subnet.nodes.id
    os_sku                       = "AzureLinux"
    only_critical_addons_enabled = var.app_pool != null
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
    pod_cidr            = "192.168.0.0/16"
    service_cidr        = "172.16.0.0/16"
    dns_service_ip      = "172.16.0.10"
  }

  dynamic "monitor_metrics" {
    for_each = var.prometheus_dcr_id == null ? [] : [1]
    content {}
  }

  tags = var.tags

  lifecycle {
    # Patch auto-upgrade moves the version; don't fight it.
    ignore_changes = [kubernetes_version]
  }
}

# Where practice workloads land. Labelled so scenarios can use nodeSelector/affinity.
resource "azurerm_kubernetes_cluster_node_pool" "app" {
  count = var.app_pool == null ? 0 : 1

  name                        = var.app_pool.name
  kubernetes_cluster_id       = azurerm_kubernetes_cluster.this.id
  vm_size                     = var.app_pool.vm_size
  vnet_subnet_id              = azurerm_subnet.nodes.id
  mode                        = "User"
  os_sku                      = "AzureLinux"
  auto_scaling_enabled        = true
  min_count                   = var.app_pool.min_count
  max_count                   = var.app_pool.max_count
  temporary_name_for_rotation = "${substr(var.app_pool.name, 0, 9)}tmp"
  node_labels                 = { "adtech.io/role" = var.app_pool.name }
  tags                        = var.tags

  upgrade_settings {
    max_surge = "10%"
  }

  lifecycle {
    ignore_changes = [node_count, orchestrator_version]
  }
}

resource "azurerm_role_assignment" "subnet_network_contributor" {
  scope                = azurerm_subnet.nodes.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.this.identity[0].principal_id
}

resource "azurerm_monitor_data_collection_rule_association" "prometheus" {
  count = var.prometheus_dcr_id == null ? 0 : 1

  name                    = "prometheus-${var.name}"
  target_resource_id      = azurerm_kubernetes_cluster.this.id
  data_collection_rule_id = var.prometheus_dcr_id
}

module "flux" {
  count  = var.gitops == null ? 0 : 1
  source = "../flux-bootstrap"

  cluster_id                  = azurerm_kubernetes_cluster.this.id
  kubelet_identity_object_id  = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
  chart_registry_id           = var.gitops.chart_registry_id
  chart_registry_login_server = var.gitops.chart_registry_login_server
  git                         = var.gitops.git
  wave_path                   = var.gitops.wave_path
  role                        = var.gitops.role
  facts                       = merge({ CLUSTER_NAME = var.name }, var.gitops.facts)

  depends_on = [azurerm_kubernetes_cluster_node_pool.app]
}
