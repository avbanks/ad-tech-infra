variable "workspace_name" {
  description = "Azure Monitor Workspace name; also used to name the DCE, DCR and rule groups."
  type        = string
}

variable "location" {
  description = "Region for the workspace, DCE, DCR, rule groups and Grafana."
  type        = string
}

variable "resource_group_name" {
  type = string
}

variable "admin_group_object_id" {
  description = "Entra group granted Grafana Admin and Monitoring Data Reader on the workspace."
  type        = string
}

variable "grafana" {
  description = "Azure Managed Grafana linked to the workspace. null = no Grafana."
  type = object({
    name          = string
    sku           = optional(string, "Standard")
    major_version = optional(string, "12") # Standard SKU accepts 12 or 13 (11 rejected as of 2026-11)
  })
  default = null

  validation {
    condition     = var.grafana == null || can(regex("^[a-zA-Z][-a-zA-Z0-9]{0,21}[a-zA-Z0-9]$", var.grafana.name))
    error_message = "Grafana name must be 2-23 chars: letters, digits and hyphens, starting with a letter."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
