variable "name" {
  description = "Globally unique, 5-50 alphanumerics (becomes <name>.azurecr.io)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{5,50}$", var.name))
    error_message = "ACR names are 5-50 lowercase alphanumerics."
  }
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "sku" {
  type    = string
  default = "Basic"
}

variable "pusher_object_ids" {
  description = "Principals allowed to push charts (CI identity, platform admins group)."
  type        = list(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
