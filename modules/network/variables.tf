variable "name_prefix" {
  description = "Prefix for regional resources, e.g. adtech-dev-eus2."
  type        = string
}

variable "location" {
  type = string
}

variable "address_space" {
  description = "Regional VNet CIDR (a /16). Must be unique across all regions so regions can be peered later."
  type        = string

  validation {
    condition     = can(cidrhost(var.address_space, 0)) && endswith(var.address_space, "/16")
    error_message = "address_space must be a valid /16 CIDR."
  }
}

variable "role_subnet_blocks" {
  description = "Role => block index. Cluster subnet = /24 number (block * 16 + cell). Keeps subnets stable when roles are added."
  type        = map(number)
}

variable "clusters_per_role" {
  description = "Number of cells (clusters per role) in this region."
  type        = number

  validation {
    condition     = var.clusters_per_role >= 1 && var.clusters_per_role <= 15
    error_message = "clusters_per_role must be between 1 and 15 (16 /24s per role block)."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
