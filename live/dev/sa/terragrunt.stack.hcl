# Continent "sa": one Fleet Manager (with hub) + two paired regions, 18 member clusters.
locals {
  continent = "sa"
  pair      = read_terragrunt_config(find_in_parent_folders("regions.hcl")).locals.continents[local.continent]
}

unit "fleet" {
  source = "${get_repo_root()}/units/fleet"
  path   = "fleet"
  values = {
    continent = local.continent
    primary   = local.pair.primary
    secondary = local.pair.secondary
  }
}

stack "primary" {
  source = "${get_repo_root()}/stacks/region"
  path   = local.pair.primary.location
  values = merge(local.pair.primary, {
    continent  = local.continent
    fleet_path = "../../../fleet" # from <continent>/.terragrunt-stack/<region>/.terragrunt-stack/<cluster>
  })
}

stack "secondary" {
  source = "${get_repo_root()}/stacks/region"
  path   = local.pair.secondary.location
  values = merge(local.pair.secondary, {
    continent  = local.continent
    fleet_path = "../../../fleet"
  })
}
