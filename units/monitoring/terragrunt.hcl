include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  env    = include.root.locals.env
  prefix = "${local.env.project}-${local.env.environment}"
}

terraform {
  source = "${get_repo_root()}/modules/monitoring"
}

inputs = {
  workspace_name        = "amw-${local.prefix}"
  location              = local.env.monitoring.location
  resource_group_name   = "rg-${local.prefix}-monitoring"
  admin_group_object_id = local.env.admin_group_id
  grafana               = local.env.monitoring.grafana_enabled ? { name = "amg-${local.prefix}" } : null

  tags = merge(include.root.inputs.tags, { scope = "global" })
}
