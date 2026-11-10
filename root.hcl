# Shared Terragrunt config. Every unit (generated from units/ by the stacks under live/) includes this.

locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals

  # Generated stack units live under ".terragrunt-stack/" dirs; strip that so state keys stay readable:
  #   ad-tech-infra/dev/na/eastus2/kafka-01/terraform.tfstate
  state_key = trimprefix(replace(path_relative_to_include(), ".terragrunt-stack/", ""), "live/")
}

remote_state {
  backend = "azurerm"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    subscription_id      = local.env.state.subscription_id
    resource_group_name  = local.env.state.resource_group_name
    storage_account_name = local.env.state.storage_account_name
    container_name       = local.env.state.container_name
    key                  = "ad-tech-infra/${local.state_key}/terraform.tfstate"
  }
}

# Modules declare required_providers; only provider configuration is generated here.
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "azurerm" {
      features {}
      subscription_id = "${local.env.subscription_id}"

      # Not in azurerm's default "core" set: Azure Monitor Workspace, Managed Grafana, Prometheus rule groups.
      resource_providers_to_register = ["Microsoft.Monitor", "Microsoft.Dashboard", "Microsoft.AlertsManagement"]
    }
  EOF
}


inputs = {
  tags = {
    project    = local.env.project
    env        = local.env.environment
    managed-by = "opentofu-terragrunt"
    repo       = "ad-tech-infra"
  }
}
