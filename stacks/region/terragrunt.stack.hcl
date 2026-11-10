# One region = one VNet + 3 cells (ingest/kafka/flink per cell) = 9 AKS clusters, each with its own state.
# Values in: location, short, cidr_index, continent, fleet_path, [vm_size_overrides]
#
# Terragrunt stacks can't loop, so cells are spelled out. Keep in sync with env.hcl clusters_per_role.

unit "network" {
  source = "${get_repo_root()}/units/network"
  path   = "network"
  values = values
}

unit "ingest_01" {
  source = "${get_repo_root()}/units/aks-cluster"
  path   = "ingest-01"
  values = merge(values, { role = "ingest", cell = 1 })
}

unit "kafka_01" {
  source = "${get_repo_root()}/units/aks-cluster"
  path   = "kafka-01"
  values = merge(values, { role = "kafka", cell = 1 })
}

unit "flink_01" {
  source = "${get_repo_root()}/units/aks-cluster"
  path   = "flink-01"
  values = merge(values, { role = "flink", cell = 1 })
}

unit "ingest_02" {
  source = "${get_repo_root()}/units/aks-cluster"
  path   = "ingest-02"
  values = merge(values, { role = "ingest", cell = 2 })
}

unit "kafka_02" {
  source = "${get_repo_root()}/units/aks-cluster"
  path   = "kafka-02"
  values = merge(values, { role = "kafka", cell = 2 })
}

unit "flink_02" {
  source = "${get_repo_root()}/units/aks-cluster"
  path   = "flink-02"
  values = merge(values, { role = "flink", cell = 2 })
}

unit "ingest_03" {
  source = "${get_repo_root()}/units/aks-cluster"
  path   = "ingest-03"
  values = merge(values, { role = "ingest", cell = 3 })
}

unit "kafka_03" {
  source = "${get_repo_root()}/units/aks-cluster"
  path   = "kafka-03"
  values = merge(values, { role = "kafka", cell = 3 })
}

unit "flink_03" {
  source = "${get_repo_root()}/units/aks-cluster"
  path   = "flink-03"
  values = merge(values, { role = "flink", cell = 3 })
}
