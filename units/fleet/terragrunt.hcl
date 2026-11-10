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

# Only the fleet module uses azapi (hubless fleet, auto-upgrade profile).
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
  name                = "fleet-${local.prefix}"
  location            = values.primary.location
  resource_group_name = "rg-${local.prefix}-fleet"
  auto_upgrade        = local.env.fleet_auto_upgrade

  # Update groups == waves (each member's group is set by the aks-cluster unit from its wave).
  # wave-1: primary cell 01 | wave-2: primary cells 02-03 | wave-3: secondary region.
  update_stages = [
    { name = "wave-1", groups = ["wave-1"], after_stage_wait_seconds = local.env.fleet_stage_wait_seconds },
    { name = "wave-2", groups = ["wave-2"], after_stage_wait_seconds = local.env.fleet_stage_wait_seconds },
    { name = "wave-3", groups = ["wave-3"] },
  ]

  tags = merge(include.root.inputs.tags, { continent = values.continent })
}
