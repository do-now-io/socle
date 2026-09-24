# --- Deployment identity ---

variable "cluster_name" {
  description = "Name shared by the resource group (when created), the VNet, the AKS cluster and every resource this module creates around them."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,62}$", var.cluster_name))
    error_message = "cluster_name must be 1-63 characters, starting with a letter or digit, and contain only letters, digits, hyphens and underscores — the AKS cluster name constraint."
  }
}

variable "owner" {
  description = "Stamped on every billable resource so cost can be attributed and orphans can be found."
  type        = string
}

variable "environment" {
  description = "Stamped on every billable resource. Also what the factory's upgrade rings (dev/staging/prod) key off."
  type        = string
}

variable "additional_tags" {
  description = "Extra tags merged onto every resource this module creates, on top of owner/environment/socle-version."
  type        = map(string)
  default     = {}
}

# --- Network — docs/azure/network-security.md ---

variable "location" {
  description = "Azure region for every resource this module creates. Required, no default — there is no globally correct region to pick on a client's behalf."
  type        = string
}

variable "create_resource_group" {
  description = "Create the resource group, or attach to one the consumer already manages."
  type        = bool
  default     = true
}

variable "resource_group_name" {
  description = "Name of the resource group. Used as the name to create when create_resource_group is true, or the name of an existing one to attach to when false."
  type        = string
}

variable "create_vnet" {
  description = "Create the VNet and its node subnet, or attach to a subnet the consumer already manages."
  type        = bool
  default     = true
}

variable "vnet_name" {
  description = "Existing VNet name to attach to. Required when create_vnet is false, and incoherent to set when create_vnet is true — this module cannot both create a VNet and attach to a different one."
  type        = string
  default     = null

  validation {
    condition     = var.create_vnet == (var.vnet_name == null)
    error_message = "vnet_name must be set when create_vnet is false, and left null when create_vnet is true."
  }
}

variable "node_subnet_id" {
  description = "Existing node subnet ID to attach to. Required when create_vnet is false — this module carves its own subnet out of vnet_cidr only when it also creates the VNet."
  type        = string
  default     = null

  validation {
    condition     = var.create_vnet == (var.node_subnet_id == null)
    error_message = "node_subnet_id must be set when create_vnet is false, and left null when create_vnet is true."
  }
}

variable "vnet_cidr" {
  description = "CIDR for the VNet — and its single node subnet, which covers the whole range — when this module creates it. Arbitrary default (not a research decision), sized generously since it only ever needs to fit nodes: Cilium's own IPAM owns pod addressing entirely, decoupled from the VNet."
  type        = string
  default     = "10.0.0.0/16"
}

variable "zones" {
  description = "Availability zones the default system node pool spreads across. Azure subnets aren't zone-scoped — zone placement happens on the node pool itself."
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "create_nat_gateway" {
  description = <<-EOT
    Create one NAT Gateway for the VNet's node subnet. Not a toggle for
    disabling egress outright — the node subnet has no public IP of its
    own, so without this its nodes reach nothing. Exists only for the
    create_vnet = false case, where the consumer's existing VNet already
    manages its own NAT or an alternate egress path.
  EOT
  type        = bool
  default     = true

  validation {
    condition     = var.create_nat_gateway || !var.create_vnet
    error_message = "create_nat_gateway can only be false when create_vnet is also false. A VNet this module creates has no other egress path for its node subnet."
  }
}

variable "service_cidr" {
  description = "CIDR for Kubernetes service IPs. Must not overlap the VNet or any connected network, and be smaller than /12 — an AKS constraint independent of the BYO CNI choice below."
  type        = string
  default     = "10.1.0.0/16"
}

variable "dns_service_ip" {
  description = "IP address within service_cidr used for cluster service discovery (kube-dns)."
  type        = string
  default     = "10.1.0.10"
}

variable "pod_cidr" {
  description = <<-EOT
    Range Cilium allocates pod addresses from, as the cluster pool of the
    Cilium the bootstrap module installs (docs/catalog/cilium.md). Not set on
    the cluster: azurerm refuses pod_cidr under network_plugin = "none" (see
    cluster.tf), so this module only carries the value to the bootstrap
    through its output. Must not overlap the VNet, service_cidr or any
    connected network. The default is AKS's own pod range, which the chart's
    default (10.0.0.0/8) would not be: that one contains the VNet.
  EOT
  type        = string
  default     = "10.244.0.0/16"
  nullable    = false

  validation {
    condition     = can(cidrhost(var.pod_cidr, 0)) && can(regex("/", var.pod_cidr))
    error_message = "pod_cidr must be an IPv4 CIDR such as 10.244.0.0/16."
  }
}

# --- Cluster — docs/azure/cluster-mode.md, docs/azure/managed-scope.md ---

variable "kubernetes_version" {
  description = "AKS control plane version. Required, no default: the module accepts whatever version it is given rather than enforcing a version policy itself — that policy is decided and bumped by the socle Kargo pipelines, not by this module."
  type        = string

  validation {
    condition     = can(regex("^1\\.\\d+$", var.kubernetes_version))
    error_message = "kubernetes_version must look like \"1.34\" (major.minor, no patch — AKS versions Kubernetes at that granularity)."
  }
}

variable "system_node_pool_vm_size" {
  description = "VM size for the mandatory system node pool. This is a structural AKS requirement, not a Karpenter/NAP-managed pool — kept small and tainted for-system-only by default (only_critical_addons_enabled), since NAP provisions everything workload-shaped."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "system_node_pool_node_count" {
  description = "Node count for the mandatory system node pool. Small and fixed rather than autoscaled: this pool exists to satisfy AKS's structural minimum, not to run workloads."
  type        = number
  default     = 2

  validation {
    condition     = var.system_node_pool_node_count >= 1
    error_message = "system_node_pool_node_count must be at least 1 — AKS cannot exist with zero nodes in its default node pool."
  }
}

variable "log_retention_days" {
  description = "Retention for the Container Insights Log Analytics workspace this module creates."
  type        = number
  default     = 90

  validation {
    condition     = contains([30, 31, 60, 90, 120, 180, 270, 365, 550, 730], var.log_retention_days)
    error_message = "log_retention_days must be one of the retention periods a Log Analytics workspace accepts (30, 31, 60, 90, 120, 180, 270, 365, 550, 730)."
  }
}

# Both windows are required, with no default: stable auto-triggers upgrades
# within maintenance_window_auto_upgrade, and node OS patching runs within
# maintenance_window_node_os on its own separate schedule — there is no
# universally correct window to pick on a client's behalf, so the module
# forces a decision rather than picking a silent one.
variable "maintenance_window_auto_upgrade" {
  description = "Window Kubernetes version auto-upgrades (stable channel) are allowed to run in. At least 4 hours, per AKS's own constraint."
  type = object({
    frequency   = string
    interval    = number
    duration    = number
    day_of_week = optional(string)
    start_time  = optional(string)
    utc_offset  = optional(string)
  })

  validation {
    condition     = var.maintenance_window_auto_upgrade.duration >= 4 && var.maintenance_window_auto_upgrade.duration <= 24
    error_message = "maintenance_window_auto_upgrade.duration must be between 4 and 24 hours — the range AKS accepts."
  }
}

variable "maintenance_window_node_os" {
  description = "Window node OS security patches are allowed to run in. Separate schedule from maintenance_window_auto_upgrade, so node patching and Kubernetes upgrades never have to share a window."
  type = object({
    frequency   = string
    interval    = number
    duration    = number
    day_of_week = optional(string)
    start_time  = optional(string)
    utc_offset  = optional(string)
  })

  validation {
    condition     = var.maintenance_window_node_os.duration >= 4 && var.maintenance_window_node_os.duration <= 24
    error_message = "maintenance_window_node_os.duration must be between 4 and 24 hours — the range AKS accepts."
  }
}
