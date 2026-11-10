locals {
  # { "ingest-01" = 1, "kafka-01" = 17, "flink-01" = 33, ... }
  cluster_subnets = merge([
    for role, block in var.role_subnet_blocks : {
      for cell in range(1, var.clusters_per_role + 1) :
      format("%s-%02d", role, cell) => block * 16 + cell
    }
  ]...)
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.name_prefix}"
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.name_prefix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.address_space]
  tags                = var.tags
}

# One node subnet per cluster. Pods use Azure CNI Overlay so they don't consume VNet IPs;
# a /24 is plenty for nodes plus internal load balancers (Kafka/ingest endpoints).
resource "azurerm_subnet" "cluster" {
  for_each = local.cluster_subnets

  name                 = "snet-${each.key}"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [cidrsubnet(var.address_space, 8, each.value)]
}

resource "azurerm_network_security_group" "cluster" {
  name                = "nsg-${var.name_prefix}-aks"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "cluster" {
  for_each = azurerm_subnet.cluster

  subnet_id                 = each.value.id
  network_security_group_id = azurerm_network_security_group.cluster.id
}
