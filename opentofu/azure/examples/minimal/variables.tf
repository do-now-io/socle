variable "location" {
  description = "Azure region for the cluster and its resource group."
  type        = string
  default     = "francecentral"
}

variable "cluster_name" {
  description = "Name of the cluster."
  type        = string
  default     = "socle-minimal"
}

variable "resource_group_name" {
  description = "Name of the resource group the cluster and its resources are created in."
  type        = string
  default     = "socle-minimal"
}

variable "owner" {
  description = "Team accountable for the cluster."
  type        = string
  default     = "platform"
}

variable "environment" {
  description = "Environment this cluster serves."
  type        = string
  default     = "dev"
}

variable "zones" {
  description = "Availability zones the default system node pool spreads across. Not every subscription/region/VM-size combination has all three available — override if the module's default fails with AvailabilityZoneNotSupported."
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "system_node_pool_vm_size" {
  description = "VM size for the mandatory system node pool. Override if the module's default is unavailable in your subscription's quota for this region."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "kubernetes_version" {
  description = "AKS control plane version. The default tracks the n-1 policy ceiling — not the newest AKS offers, and not one close to the end of its standard support."
  type        = string
  default     = "1.36"
}

variable "maintenance_window_auto_upgrade" {
  description = "Window Kubernetes version auto-upgrades are allowed to run in."
  type = object({
    frequency   = string
    interval    = number
    duration    = number
    day_of_week = optional(string)
    start_time  = optional(string)
    utc_offset  = optional(string)
  })
  default = {
    frequency   = "Weekly"
    interval    = 1
    duration    = 4
    day_of_week = "Sunday"
    start_time  = "02:00"
    utc_offset  = "+00:00"
  }
}

variable "maintenance_window_node_os" {
  description = "Window node OS security patches are allowed to run in."
  type = object({
    frequency   = string
    interval    = number
    duration    = number
    day_of_week = optional(string)
    start_time  = optional(string)
    utc_offset  = optional(string)
  })
  default = {
    frequency   = "Weekly"
    interval    = 1
    duration    = 4
    day_of_week = "Saturday"
    start_time  = "03:00"
    utc_offset  = "+00:00"
  }
}
