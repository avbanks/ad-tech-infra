include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  env    = include.root.locals.env
  prefix = "${local.env.project}-${local.env.environment}-${values.continent}"
}

terraform {
  source = "${get_repo_root()}/modules/fleet"
}

# Only the fleet module uses azapi (hub profile, auto-upgrade profile).
generate "azapi_provider" {
  path      = "azapi_provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "azapi" {
      subscription_id = "${local.env.subscription_id}"
    }
  EOF
}

inputs = {
  name                  = "fleet-${local.prefix}"
  location              = values.primary.location
  resource_group_name   = "rg-${local.prefix}-fleet"
  hub_vm_size           = local.env.fleet_hub_vm_size
  admin_group_object_id = local.env.admin_group_id
  auto_upgrade          = local.env.fleet_auto_upgrade

  # Update groups == region names (set on each fleet member by the aks-cluster unit).
  update_stages = [
    {
      name                     = "primary-${values.primary.location}"
      groups                   = [values.primary.location]
      after_stage_wait_seconds = local.env.fleet_stage_wait_seconds
    },
    {
      name   = "secondary-${values.secondary.location}"
      groups = [values.secondary.location]
    },
  ]

  tags = merge(include.root.inputs.tags, { continent = values.continent })
}
