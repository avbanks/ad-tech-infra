# Practice clusters, outside the ad-tech fleet. Settings: env.hcl debug_cluster.
#   make apply-debug / make destroy-debug
unit "debug" {
  source = "${get_repo_root()}/units/debug-cluster"
  path   = "debug"
}
