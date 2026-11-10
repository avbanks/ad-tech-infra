# Dev environment settings. Subscription/tenant/admin group/state backend come from ~/Repos/mock-infra.
locals {
  project         = "adtech"
  environment     = "dev"
  subscription_id = "ed60c73d-d33c-4af6-bcd5-ab95ce2bcf0d"
  tenant_id       = "a082630b-4636-47a2-ad8d-a514945d1709"
  admin_group_id  = "71e4ecd1-c17f-4a7d-8e4d-2621218d9044"

  state = {
    subscription_id      = "ed60c73d-d33c-4af6-bcd5-ab95ce2bcf0d"
    resource_group_name  = "tfstate-rg"
    storage_account_name = "tfstateabanks"
    container_name       = "tfstate"
  }

  # ---- AKS (cheap dev settings) ----
  kubernetes_version = null                 # AKS default; Fleet owns upgrades afterwards
  aks_sku_tier       = "Free"               # no uptime SLA in dev
  system_vm_size     = "Standard_D2alds_v6" # 2 vCPU / 4 GiB, AMD, local temp disk

  # Cells per region: cell N = ingest-0N + kafka-0N + flink-0N.
  # NOTE: stacks/region/terragrunt.stack.hcl declares one unit per cluster - keep the two in sync.
  clusters_per_role = 3

  # subnet_block: cluster subnet = 10.<region>.<subnet_block*16 + cell>.0/24 (stable when roles are added).
  roles = {
    ingest = { subnet_block = 0, vm_size = "Standard_D2alds_v6", min_count = 1, max_count = 2 } # 2 vCPU / 4 GiB
    kafka  = { subnet_block = 1, vm_size = "Standard_D2ads_v6", min_count = 1, max_count = 2 }  # 2 vCPU / 8 GiB
    flink  = { subnet_block = 2, vm_size = "Standard_D2ads_v6", min_count = 1, max_count = 2 }  # 2 vCPU / 8 GiB
  }

  # ---- Fleet Manager (hubless; Kubernetes upgrades only) ----
  fleet_stage_wait_seconds = 600  # bake between waves when the full "waves" strategy is used (dev: 10 min)
  fleet_auto_upgrade       = null # off: start runs by hand, one wave at a time (scripts/fleet-upgrade.sh)

  # ---- Monitoring (Azure Managed Prometheus) ----
  # One global Azure Monitor Workspace for every cluster in the env; clusters in all regions send to it.
  monitoring = {
    location        = "eastus2"
    grafana_enabled = true # Azure Managed Grafana (Standard) linked to the workspace
  }

  # ---- Practice cluster (live/dev/sandbox) - standalone, not a fleet member ----
  # eastus2 has a 10 vCPU quota: system (2) + apps (2-4) = 4-6 vCPU. NA fleet/cells need the rest.
  debug_cluster = {
    location      = "eastus2"
    short         = "eus2"
    continent     = "na"
    address_space = "10.99.0.0/16"      # outside every region's 10.<cidr_index>/16
    vm_size       = "Standard_D2ads_v6" # system pool: 2 vCPU / 8 GiB, tainted CriticalAddonsOnly
    node_count    = 1
    # Workloads land here (label adtech.io/role=apps). Autoscales 1-2 nodes.
    app_pool = { vm_size = "Standard_D2ads_v6", min_count = 1, max_count = 2 }
  }
}
