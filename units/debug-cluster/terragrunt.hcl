include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  env = include.root.locals.env
  cfg = local.env.debug_cluster
}

terraform {
  source = "${get_repo_root()}/modules/debug-cluster"
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

  # role=debug: scripts/deploy-k8s.sh picks it up and helmfile installs only the platform releases.
  tags = merge(include.root.inputs.tags, {
    continent = local.cfg.continent
    region    = local.cfg.location
    role      = "debug"
    purpose   = "k8s-troubleshooting-practice"
  })
}
