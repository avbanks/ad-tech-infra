include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  env      = include.root.locals.env
  role     = values.role
  role_cfg = local.env.roles[local.role]
  cell     = format("%02d", values.cell)
  key      = "${local.role}-${local.cell}" # e.g. kafka-02 (matches network subnet keys)
  name     = "aks-${local.env.environment}-${values.short}-${local.key}"

  # Kafka for this cell lives on 10.<region>.<kafka block*16+cell>.0/24. Strimzi's internal LB
  # listener pins bootstrap to .250 and brokers to .251+, so ingest/flink in the same cell can
  # find Kafka without service discovery. Published as a tag; read by scripts/deploy-k8s.sh.
  kafka_ip_prefix = "10.${values.cidr_index}.${local.env.roles.kafka.subnet_block * 16 + values.cell}"

  mock_rg = "/subscriptions/${local.env.subscription_id}/resourceGroups/rg-mock"
}

terraform {
  source = "${get_repo_root()}/modules/aks-cluster"
}

dependency "network" {
  config_path = "../network"

  mock_outputs = {
    resource_group_name = "rg-mock"
    subnet_ids = {
      (local.key) = "${local.mock_rg}/providers/Microsoft.Network/virtualNetworks/vnet-mock/subnets/snet-${local.key}"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "fleet" {
  config_path = values.fleet_path

  mock_outputs = {
    fleet_id = "${local.mock_rg}/providers/Microsoft.ContainerService/fleets/fleet-mock"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

# Global (env-wide) metrics workspace: live/<env>/global, applied once before any continent.
dependency "monitoring" {
  config_path = "${dirname(find_in_parent_folders("env.hcl"))}/global/.terragrunt-stack/monitoring"

  mock_outputs = {
    data_collection_rule_id = "${local.mock_rg}/providers/Microsoft.Insights/dataCollectionRules/dcr-mock"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  name                   = local.name
  location               = values.location
  resource_group_name    = dependency.network.outputs.resource_group_name
  subnet_id              = dependency.network.outputs.subnet_ids[local.key]
  tenant_id              = local.env.tenant_id
  admin_group_object_ids = [local.env.admin_group_id]
  kubernetes_version     = local.env.kubernetes_version
  sku_tier               = local.env.aks_sku_tier

  # Per-region overrides for regions where a SKU isn't offered: values.vm_size_overrides = { system = "...", kafka = "..." }
  system_vm_size = try(values.vm_size_overrides.system, local.env.system_vm_size)
  app_pool = {
    name      = local.role
    vm_size   = try(values.vm_size_overrides[local.role], local.role_cfg.vm_size)
    min_count = local.role_cfg.min_count
    max_count = local.role_cfg.max_count
    labels    = { "adtech.io/cell" = local.cell }
  }

  fleet_id           = dependency.fleet.outputs.fleet_id
  fleet_update_group = local.wave # Fleet update runs stage by wave, same grouping as app releases

  prometheus_dcr_id = dependency.monitoring.outputs.data_collection_rule_id

  # Tags double as the inventory that scripts/deploy-k8s.sh uses to pick helmfile values.
  tags = merge(include.root.inputs.tags, {
    continent     = values.continent
    region        = values.location
    role          = local.role
    cell          = local.cell
    kafkaIpPrefix = local.kafka_ip_prefix
  })
}
