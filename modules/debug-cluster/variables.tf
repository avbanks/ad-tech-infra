variable "name" {
  type = string
}

variable "name_prefix" {
  description = "Prefix for the RG/VNet/NSG, e.g. adtech-dev-eus2-debug."
  type        = string
}

variable "location" {
  type = string
}

variable "address_space" {
  description = "VNet CIDR (/16). Nodes get the second /24. Keep it unique so it never collides with a region."
  type        = string

  validation {
    condition     = can(cidrhost(var.address_space, 0)) && endswith(var.address_space, "/16")
    error_message = "address_space must be a valid /16 CIDR."
  }
}

variable "vm_size" {
  type = string
}

variable "node_count" {
  type    = number
  default = 1
}

variable "app_pool" {
  description = "User pool for workloads. null = single tainted-free system pool runs everything."
  type = object({
    name      = optional(string, "apps")
    vm_size   = string
    min_count = optional(number, 1)
    max_count = optional(number, 2)
  })
  default = null

  validation {
    condition     = var.app_pool == null || can(regex("^[a-z][a-z0-9]{0,11}$", var.app_pool.name))
    error_message = "Linux node pool names must be 1-12 lowercase alphanumerics starting with a letter."
  }

  validation {
    condition     = var.app_pool == null || (var.app_pool.min_count >= 0 && var.app_pool.max_count >= var.app_pool.min_count)
    error_message = "app_pool.max_count must be >= min_count >= 0."
  }
}

variable "kubernetes_version" {
  description = "null = AKS default at creation; patch auto-upgrade takes over afterwards."
  type        = string
  default     = null
}

variable "tenant_id" {
  type = string
}

variable "admin_group_object_ids" {
  type = list(string)
}

variable "prometheus_dcr_id" {
  description = "Managed Prometheus DCR. null = metrics add-on disabled."
  type        = string
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "gitops" {
  description = "Flux bootstrap (same shape as modules/aks-cluster). null = no Flux."
  type = object({
    git = object({
      repo_url = string
      branch   = optional(string, "main")
      token    = optional(string, "")
    })
    chart_registry_id           = string
    chart_registry_login_server = string
    wave_path                   = string
    role                        = string
    facts                       = map(string)
  })
  default   = null
  sensitive = true
}
