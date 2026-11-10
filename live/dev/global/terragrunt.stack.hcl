# Environment-wide resources shared by every continent. Apply before any continent:
#   make apply-global
unit "monitoring" {
  source = "${get_repo_root()}/units/monitoring"
  path   = "monitoring"
}
