include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  env    = include.root.locals.env
  prefix = "${local.env.project}-${local.env.environment}"
}

terraform {
  source = "${get_repo_root()}/modules/registry"
}

inputs = {
  name                = local.env.registry.name
  location            = local.env.registry.location
  resource_group_name = "rg-${local.prefix}-registry"
  sku                 = local.env.registry.sku
  pusher_object_ids   = [local.env.admin_group_id]

  tags = merge(include.root.inputs.tags, { scope = "global" })
}
