# Installs Flux (AKS extension) and tells it which two directories this cluster follows:
#   wave: k8s/waves/<env>/<continent>/<wave>  -> the "versions" ConfigMap (edited by promotions)
#   role: k8s/base/<role>                      -> HelmReleases etc., with ${FACTS} and ${VERSIONS} substituted
# After this, Terraform is out of the release path: what runs and which version is a git change.

resource "azurerm_kubernetes_cluster_extension" "flux" {
  name           = "flux"
  cluster_id     = var.cluster_id
  extension_type = "microsoft.flux"
  release_train  = "Stable"
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = var.chart_registry_id
  role_definition_name = "AcrPull"
  principal_id         = var.kubelet_identity_object_id
}

resource "azurerm_kubernetes_flux_configuration" "platform" {
  name       = "platform"
  cluster_id = var.cluster_id
  namespace  = "flux-system"
  scope      = "cluster"

  git_repository {
    url                      = var.git.repo_url
    reference_type           = "branch"
    reference_value          = var.git.branch
    sync_interval_in_seconds = 60
    timeout_in_seconds       = 120
    https_user               = var.git.token == "" ? null : "git"
    https_key_base64         = var.git.token == "" ? null : base64encode(var.git.token)
  }

  # Objects are named <config>-<kustomization>: platform-wave, platform-role.
  kustomizations {
    name                       = "wave"
    path                       = "./${var.wave_path}"
    sync_interval_in_seconds   = 60
    retry_interval_in_seconds  = 60
    garbage_collection_enabled = true
    wait                       = true
  }

  kustomizations {
    name                       = "role"
    path                       = "./k8s/base/${var.role}"
    depends_on                 = ["wave"]
    sync_interval_in_seconds   = 60
    retry_interval_in_seconds  = 120
    timeout_in_seconds         = 900
    garbage_collection_enabled = true
    wait                       = true # Ready only when every HelmRelease it applied is Ready -> commit status means "healthy"

    post_build {
      substitute = merge(var.facts, {
        CHART_REGISTRY  = var.chart_registry_login_server
        GITOPS_REPO_URL = trimsuffix(var.git.repo_url, ".git")
      })

      substitute_from {
        kind     = "ConfigMap"
        name     = "versions"
        optional = false
      }
    }
  }

  depends_on = [azurerm_kubernetes_cluster_extension.flux, azurerm_role_assignment.acr_pull]
}
