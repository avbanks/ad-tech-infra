include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  env = include.root.locals.env
}

terraform {
  source = "${get_repo_root()}/modules/network"
}

inputs = {
  name_prefix        = "${local.env.project}-${local.env.environment}-${values.short}"
  location           = values.location
  address_space      = "10.${values.cidr_index}.0.0/16"
  role_subnet_blocks = { for role, cfg in local.env.roles : role => cfg.subnet_block }
  clusters_per_role  = local.env.clusters_per_role
  tags               = merge(include.root.inputs.tags, { continent = values.continent, region = values.location })
}
