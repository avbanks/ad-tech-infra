variable "name" {
  type = string

  validation {
    condition     = can(regex("^[a-z0-9][-a-z0-9]{0,48}[a-z0-9]$", var.name))
    error_message = "Cluster name must be <= 50 chars, lowercase alphanumerics and hyphens (also used as the Fleet member name)."
  }
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "subnet_id" {
  description = "Node subnet for both system and app pools."
  type        = string
}

variable "kubernetes_version" {
  description = "null = AKS default. After creation, Fleet update runs own upgrades (changes are ignored here)."
  type        = string
  default     = null
}

variable "sku_tier" {
  type    = string
  default = "Free"

  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.sku_tier)
    error_message = "sku_tier must be Free, Standard or Premium."
  }
}

variable "tenant_id" {
  type = string
}

variable "admin_group_object_ids" {
  type = list(string)
}

variable "system_vm_size" {
  type = string
}

variable "system_node_count" {
  type    = number
  default = 1
}

variable "app_pool" {
  description = "The single workload node pool for this cluster's role."
  type = object({
    name      = string
    vm_size   = string
    min_count = number
    max_count = number
    labels    = optional(map(string), {})
  })

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{0,11}$", var.app_pool.name))
    error_message = "Linux node pool names must be 1-12 lowercase alphanumerics starting with a letter."
  }

  validation {
    condition     = var.app_pool.min_count >= 0 && var.app_pool.max_count >= var.app_pool.min_count
    error_message = "app_pool.max_count must be >= min_count >= 0."
  }
}

variable "network" {
  description = "Overlay CIDRs. Safe to reuse across clusters because pods/services are not routable on the VNet."
  type = object({
    pod_cidr       = optional(string, "192.168.0.0/16")
    service_cidr   = optional(string, "172.16.0.0/16")
    dns_service_ip = optional(string, "172.16.0.10")
  })
  default = {}
}

variable "fleet_id" {
  description = "Fleet Manager resource ID to join."
  type        = string
}

variable "fleet_update_group" {
  description = "Update group used by the fleet's update strategy (we use the region name)."
  type        = string
}

variable "prometheus_dcr_id" {
  description = "Data Collection Rule for Azure Managed Prometheus. null = metrics add-on disabled."
  type        = string
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
