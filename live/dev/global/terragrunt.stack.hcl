# Environment-wide resources shared by every continent. Apply before any continent:
#   make apply-global
unit "monitoring" {
  source = "${get_repo_root()}/units/monitoring"
  path   = "monitoring"
}

# Helm chart registry (ACR). Flux on every cluster pulls k8s/charts/* from here.
unit "registry" {
  source = "${get_repo_root()}/units/registry"
  path   = "registry"
}
