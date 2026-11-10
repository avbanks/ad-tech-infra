variable "name" {
  type = string

  validation {
    condition     = can(regex("^[a-z0-9][-a-z0-9]{0,61}[a-z0-9]$", var.name))
    error_message = "Fleet name must be lowercase alphanumerics/hyphens, <= 63 chars."
  }
}

variable "location" {
  description = "Fleet resource location - the continent's primary region."
  type        = string
}

variable "resource_group_name" {
  type = string
}

variable "update_stages" {
  description = <<-EOT
    Ordered stages of the "waves" update strategy; each stage names the update groups (= waves, set on each
    fleet member by the aks-cluster unit) it upgrades in parallel. A one-stage strategy is also created per
    stage so scripts/fleet-upgrade.sh can run a single wave and stop.
  EOT
  type = list(object({
    name                     = string
    groups                   = list(string)
    after_stage_wait_seconds = optional(number)
  }))
}

variable "auto_upgrade" {
  description = "Fleet auto-upgrade profile (channel: Stable | Rapid | NodeImage). null = off: upgrades are started by hand, wave by wave."
  type = object({
    channel = string
  })
  default = null

  validation {
    condition     = var.auto_upgrade == null || contains(["Stable", "Rapid", "NodeImage"], try(var.auto_upgrade.channel, ""))
    error_message = "auto_upgrade.channel must be Stable, Rapid or NodeImage."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
