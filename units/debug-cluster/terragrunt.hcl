include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  env = include.root.locals.env
  cfg = local.env.debug_cluster
}

terraform {
  source = "${get_repo_root()}/modules//debug-cluster"
}

dependency "registry" {
  config_path = "${dirname(find_in_parent_folders("env.hcl"))}/global/.terragrunt-stack/registry"

  mock_outputs = {
    id           = "/subscriptions/${local.env.subscription_id}/resourceGroups/rg-mock/providers/Microsoft.ContainerRegistry/registries/acrmock"
    login_server = "acrmock.azurecr.io"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "monitoring" {
  config_path = "${dirname(find_in_parent_folders("env.hcl"))}/global/.terragrunt-stack/monitoring"

  mock_outputs = {
    data_collection_rule_id = "/subscriptions/${local.env.subscription_id}/resourceGroups/rg-mock/providers/Microsoft.Insights/dataCollectionRules/dcr-mock"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  name                   = "aks-${local.env.environment}-${local.cfg.short}-debug"
  name_prefix            = "${local.env.project}-${local.env.environment}-${local.cfg.short}-debug"
  location               = local.cfg.location
  address_space          = local.cfg.address_space
  vm_size                = local.cfg.vm_size
  node_count             = local.cfg.node_count
  app_pool               = try(local.cfg.app_pool, null)
  tenant_id              = local.env.tenant_id
  admin_group_object_ids = [local.env.admin_group_id]
  prometheus_dcr_id      = dependency.monitoring.outputs.data_collection_rule_id

  # role=debug: Flux applies k8s/base/debug (platform releases only) at k8s/waves/<env>/sandbox/wave-1 versions.
  gitops = {
    git                         = local.env.gitops
    chart_registry_id           = dependency.registry.outputs.id
    chart_registry_login_server = dependency.registry.outputs.login_server
    wave_path                   = "k8s/waves/${local.env.environment}/sandbox/wave-1"
    role                        = "debug"
    facts = {
      ENVIRONMENT     = local.env.environment
      CONTINENT       = local.cfg.continent
      REGION          = local.cfg.location
      ROLE            = "debug"
      CELL            = "00"
      WAVE            = "wave-1"
      KAFKA_IP_PREFIX = ""
    }
  }

  tags = merge(include.root.inputs.tags, {
    continent = local.cfg.continent
    region    = local.cfg.location
    role      = "debug"
    wave      = "wave-1"
    purpose   = "k8s-troubleshooting-practice"
  })
}
