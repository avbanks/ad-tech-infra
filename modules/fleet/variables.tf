variable "name" {
  type = string

  validation {
    condition     = can(regex("^[a-z0-9][-a-z0-9]{0,61}[a-z0-9]$", var.name))
    error_message = "Fleet name must be lowercase alphanumerics/hyphens, <= 63 chars."
  }
}

variable "location" {
  description = "Fleet (and hub) location - the continent's primary region."
  type        = string
}

variable "resource_group_name" {
  type = string
}

variable "hub_vm_size" {
  description = "VM size for the Fleet hub cluster's single node."
  type        = string
}

variable "update_stages" {
  description = "Ordered stages; each stage lists the update groups (regions) it upgrades in parallel."
  type = list(object({
    name                     = string
    groups                   = list(string)
    after_stage_wait_seconds = optional(number)
  }))
}

variable "auto_upgrade" {
  description = "Fleet auto-upgrade profile. channel: Stable | Rapid | NodeImage. null disables it."
  type = object({
    channel = string
  })
  default = null

  validation {
    condition     = var.auto_upgrade == null || contains(["Stable", "Rapid", "NodeImage"], try(var.auto_upgrade.channel, ""))
    error_message = "auto_upgrade.channel must be Stable, Rapid or NodeImage."
  }
}

variable "admin_group_object_id" {
  description = "Entra group granted cluster-admin on the Fleet hub (to apply ClusterResourcePlacements)."
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
