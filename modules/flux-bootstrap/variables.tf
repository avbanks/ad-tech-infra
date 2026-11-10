variable "cluster_id" {
  type = string
}

variable "kubelet_identity_object_id" {
  description = "Granted AcrPull on the chart registry so Flux's HelmRepository (provider: azure) can pull."
  type        = string
}

variable "chart_registry_id" {
  type = string
}

variable "chart_registry_login_server" {
  type = string
}

variable "git" {
  description = "Repo Flux follows. token: read-only PAT for private repos, empty for anonymous."
  type = object({
    repo_url = string
    branch   = optional(string, "main")
    token    = optional(string, "")
  })
  sensitive = true
}

variable "wave_path" {
  description = "Repo path of this cluster's wave, e.g. k8s/waves/dev/na/wave-2. Holds the versions ConfigMap."
  type        = string
}

variable "role" {
  description = "Repo path k8s/base/<role> is applied with the facts below substituted in."
  type        = string
}

variable "facts" {
  description = "Flux post-build substitutions for the role base (ENVIRONMENT, REGION, CELL, KAFKA_IP_PREFIX, ...)."
  type        = map(string)
}
