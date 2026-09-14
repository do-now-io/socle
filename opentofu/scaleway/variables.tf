# Every variable is typed, every constrained value is enforced by a validation
# block rather than by documentation, and every default is the position the
# research documents recommend. Options we would not recommend are absent.

# ---------------------------------------------------------------------------
# Identity of the deployment
# ---------------------------------------------------------------------------

variable "project_id" {
  description = "Scaleway Project that holds the cluster and its network. One Project per environment: it is the only boundary Scaleway offers for both IAM and cost attribution."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.project_id))
    error_message = "project_id must be a UUID."
  }
}

variable "region" {
  description = "Scaleway region for the cluster, its network and its pools."
  type        = string
  default     = "fr-par"

  validation {
    condition     = contains(["fr-par", "nl-ams", "pl-waw"], var.region)
    error_message = "region must be one of fr-par, nl-ams or pl-waw — Scaleway has no others."
  }
}

variable "cluster_name" {
  description = "Name of the Kapsule cluster. Also names the network resources the module creates."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,38}[a-z0-9])?$", var.cluster_name))
    error_message = "cluster_name must be 1 to 40 characters of lowercase letters, digits and dashes, starting with a letter."
  }
}

variable "owner" {
  description = "Team accountable for the cluster. Stamped as a tag on every resource that takes tags."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9_-]{1,63}$", var.owner))
    error_message = "owner must be 1 to 63 characters of lowercase letters, digits, dashes and underscores."
  }
}

variable "environment" {
  description = "Environment this cluster serves. Stamped as a tag, decides the default control plane offer, and is the axis the upgrade ring order follows."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of dev, staging or prod."
  }
}

variable "additional_tags" {
  description = "Extra tags merged onto the standard set, rendered as key=value. Cannot override owner, environment, cluster or socle-version."
  type        = map(string)
  default     = {}

  validation {
    condition     = length(setintersection(keys(var.additional_tags), ["owner", "environment", "cluster", "socle-version"])) == 0
    error_message = "additional_tags must not contain owner, environment, cluster or socle-version — those are the standard tag set."
  }
}

# ---------------------------------------------------------------------------
# Network — docs/scaleway/kapsule-capabilities.md
# ---------------------------------------------------------------------------

variable "create_vpc" {
  description = "Create the VPC instead of attaching to an existing one. Routing is VPC-wide, so one VPC per environment is the layout the research recommends."
  type        = bool
  default     = true
}

variable "vpc_id" {
  description = "ID of an existing VPC to attach the cluster's Private Network to. Mutually exclusive with create_vpc."
  type        = string
  default     = null

  validation {
    condition     = var.create_vpc != (var.vpc_id != null)
    error_message = "Set vpc_id to attach to an existing VPC, or create_vpc to have the module build one — exactly one of the two."
  }
}

variable "private_network_cidr" {
  description = "IPv4 subnet of the cluster's Private Network. Kapsule consumes a /22 per cluster, so anything larger is wasted and anything smaller is refused."
  type        = string
  default     = "10.10.0.0/22"

  validation {
    condition     = can(cidrnetmask(var.private_network_cidr)) && tonumber(split("/", var.private_network_cidr)[1]) == 22
    error_message = "private_network_cidr must be a valid IPv4 /22 — Kapsule assigns exactly that to a cluster."
  }
}

variable "availability_zones" {
  description = "Zones the node pools span, one pool per zone. Two is the default because the current instance generation exists in only two zones of fr-par and nl-ams; only pl-waw offers three."
  type        = list(string)
  default     = ["fr-par-1", "fr-par-2"]

  validation {
    condition     = length(var.availability_zones) > 0 && length(var.availability_zones) == length(distinct(var.availability_zones))
    error_message = "availability_zones must hold at least one zone and no duplicates."
  }

  validation {
    condition     = alltrue([for z in var.availability_zones : can(regex("^(fr-par|nl-ams|pl-waw)-[1-3]$", z))])
    error_message = "Each availability zone must be a real Scaleway zone, such as fr-par-1."
  }

  validation {
    condition     = alltrue([for z in var.availability_zones : startswith(z, "${var.region}-")])
    error_message = "Every availability zone must belong to var.region — a cluster lives in one region."
  }
}

variable "public_gateway_type" {
  description = "Offer of the Public Gateways that carry node egress. VPC-GW-S handles 100 Mbps, which is ample for image pulls and API calls."
  type        = string
  default     = "VPC-GW-S"

  validation {
    condition     = contains(["VPC-GW-S", "VPC-GW-M", "VPC-GW-L", "VPC-GW-XL"], var.public_gateway_type)
    error_message = "public_gateway_type must be one of VPC-GW-S, VPC-GW-M, VPC-GW-L or VPC-GW-XL."
  }
}

# Controlled isolation is deliberately absent. Nodes never carry a public IP:
# dev and staging would otherwise exercise a different egress path from
# production, which is the one thing the socle exists to prevent.

# ---------------------------------------------------------------------------
# Control plane access — docs/scaleway/kapsule-capabilities.md
# ---------------------------------------------------------------------------

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the Kubernetes API server. Required with no default: the control plane cannot be made private on Kapsule, so this list is the only boundary there is, and Kapsule ships 0.0.0.0/0."
  type        = list(string)

  validation {
    condition     = length(var.cluster_endpoint_public_access_cidrs) > 0
    error_message = "cluster_endpoint_public_access_cidrs must list at least the automation's egress — an empty list would lock every client out."
  }

  validation {
    condition     = alltrue([for c in var.cluster_endpoint_public_access_cidrs : can(cidrnetmask(c))])
    error_message = "Every entry must be a valid IPv4 CIDR block."
  }

  validation {
    condition     = !contains(var.cluster_endpoint_public_access_cidrs, "0.0.0.0/0")
    error_message = "0.0.0.0/0 is refused: it is what Kapsule already ships, and restoring it defeats the only control plane boundary available."
  }
}

# ---------------------------------------------------------------------------
# Cluster — docs/scaleway/kapsule-capabilities.md
# ---------------------------------------------------------------------------

variable "kubernetes_version" {
  description = "Kubernetes minor or patch version. Required with no default: Scaleway has no release channel, auto-upgrade covers patches only, and a floating version would let the pipeline lose track of which minor is deployed."
  type        = string

  validation {
    condition     = can(regex("^1\\.[0-9]{2}(\\.[0-9]{1,2})?$", var.kubernetes_version))
    error_message = "kubernetes_version must be a Kubernetes 1.x minor such as 1.35, or a patch such as 1.35.3."
  }
}

variable "control_plane_type" {
  description = "Control plane offer. Null derives it from environment — dedicated 4 in production for the SLA and the audit log, mutualized elsewhere. Kosmos offers are absent by decision."
  type        = string
  default     = null

  validation {
    condition     = var.control_plane_type == null || contains(["kapsule", "kapsule-dedicated-4", "kapsule-dedicated-8", "kapsule-dedicated-16"], coalesce(var.control_plane_type, "kapsule"))
    error_message = "control_plane_type must be kapsule or one of kapsule-dedicated-4, -8, -16. Kosmos is refused: a different CNI, no Private Network and no migration path."
  }
}

variable "maintenance_window" {
  description = "When patch auto-upgrades may run. Required with no default: a silent default means nobody decided when production gets upgraded, and the window is what orders the upgrade rings across environments."
  type = object({
    day        = string
    start_hour = number
  })

  validation {
    condition     = contains(["any", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"], var.maintenance_window.day)
    error_message = "maintenance_window.day must be a lowercase day name, or \"any\"."
  }

  validation {
    condition     = var.maintenance_window.start_hour >= 0 && var.maintenance_window.start_hour <= 23 && floor(var.maintenance_window.start_hour) == var.maintenance_window.start_hour
    error_message = "maintenance_window.start_hour must be a whole hour between 0 and 23, in UTC."
  }
}

variable "delete_additional_resources" {
  description = "On cluster deletion, also delete the Load Balancers and Block volumes Kubernetes created. False keeps client data when a cluster is torn down, at the price of orphaned billable resources someone has to clean up."
  type        = bool
  default     = false
}

variable "autoscaler_expander" {
  description = "How the cluster-autoscaler picks which pool to grow. least_waste strands the least capacity; Scaleway's own default is random, which is a coin flip once there is more than one pool."
  type        = string
  default     = "least_waste"

  validation {
    condition     = contains(["least_waste", "most_pods", "priority", "random"], var.autoscaler_expander)
    error_message = "autoscaler_expander must be least_waste, most_pods, priority or random. price is refused: upstream implements it for GCE and AWS only, so on Scaleway it is a silent no-op."
  }
}

variable "scale_down_unneeded_time" {
  description = "How long a node must sit below the utilisation threshold before the autoscaler removes it."
  type        = string
  default     = "10m"

  validation {
    condition     = can(regex("^[0-9]+[ms]$", var.scale_down_unneeded_time))
    error_message = "scale_down_unneeded_time must be a duration such as 10m or 600s."
  }
}

variable "scale_down_utilization_threshold" {
  description = "Requested resources over allocatable capacity, below which a node becomes a scale-down candidate."
  type        = number
  default     = 0.5

  validation {
    condition     = var.scale_down_utilization_threshold > 0 && var.scale_down_utilization_threshold < 1
    error_message = "scale_down_utilization_threshold must be strictly between 0 and 1."
  }
}

# ---------------------------------------------------------------------------
# Node pools — docs/scaleway/kapsule-capabilities.md
# ---------------------------------------------------------------------------

variable "node_type" {
  description = "Commercial type of the pool nodes. COMPUTE3-X is the current generation: dedicated vCPU at 1 vCPU per 2 GiB. BASIC3-X is refused for nodes — shared vCPU and a 99% SLO."
  type        = string
  default     = "COMPUTE3-X8C-16G"

  validation {
    condition     = !can(regex("^(BASIC[23]|DEV1|PLAY2|STARDUST)", var.node_type))
    error_message = "node_type must not be a shared-vCPU or development range: BASIC2, BASIC3, DEV1, PLAY2 and STARDUST carry a 99% SLO or less and are not production nodes."
  }

  # The current generation (COMPUTE3, STANDARD3, BASIC3 — AMD Zen 5) and the
  # previous one (POP2, PRO2) never share an Availability Zone. Read from
  # /instance/v1/zones/{zone}/products/servers on 14 September 2026; Scaleway's
  # own documentation contradicts the API here, so the API is what is encoded.
  # Catching this at plan time beats discovering it when a pool fails to build.
  validation {
    condition = !can(regex("^(COMPUTE3|STANDARD3|BASIC3)", var.node_type)) || alltrue([
      for z in var.availability_zones : contains(["fr-par-1", "fr-par-2", "nl-ams-1", "nl-ams-2"], z)
    ])
    error_message = "The Zen 5 ranges (COMPUTE3, STANDARD3, BASIC3) exist only in fr-par-1, fr-par-2, nl-ams-1 and nl-ams-2. Pick zones from that set, or a POP2 type."
  }

  validation {
    condition = !can(regex("^(POP2|PRO2)", var.node_type)) || alltrue([
      for z in var.availability_zones : contains(["fr-par-3", "nl-ams-2", "nl-ams-3", "pl-waw-1", "pl-waw-2", "pl-waw-3"], z)
    ])
    error_message = "POP2 and PRO2 do not exist in fr-par-1, fr-par-2 or nl-ams-1. Only pl-waw carries them in all three zones."
  }
}

variable "pool_min_size" {
  description = "Minimum nodes per pool, and therefore per zone. Billed whether anything schedules on them or not, because the autoscaler never consolidates."
  type        = number
  default     = 2

  validation {
    condition     = var.pool_min_size >= 0 && floor(var.pool_min_size) == var.pool_min_size
    error_message = "pool_min_size must be a whole number of nodes. Zero is allowed: Kapsule supports scale to zero."
  }
}

variable "pool_max_size" {
  description = "Maximum nodes per pool, and therefore per zone."
  type        = number
  default     = 5

  validation {
    condition     = var.pool_max_size >= 1 && floor(var.pool_max_size) == var.pool_max_size && var.pool_max_size >= var.pool_min_size
    error_message = "pool_max_size must be a whole number, at least 1, and not below pool_min_size."
  }
}

variable "root_volume_size_in_gb" {
  description = "System volume of each node. Scaleway's own guidance is 20 GB minimum and 100 GB to hold images and system logs comfortably."
  type        = number
  default     = 100

  validation {
    condition     = var.root_volume_size_in_gb >= 20
    error_message = "root_volume_size_in_gb must be at least 20 — below that a node runs out of space storing system files."
  }
}

# ---------------------------------------------------------------------------
# Identities — docs/scaleway/managed-scope.md
# ---------------------------------------------------------------------------

variable "crossplane_permission_sets" {
  description = "Permission sets granted to the in-cluster Crossplane identity, scoped to this Project. Required with no default: what Crossplane may provision is a per-client decision, and a default would either be uselessly narrow or dangerously wide."
  type        = list(string)

  validation {
    condition     = length(var.crossplane_permission_sets) > 0
    error_message = "crossplane_permission_sets must name at least one permission set."
  }

  validation {
    condition     = !contains(var.crossplane_permission_sets, "AllProductsFullAccess")
    error_message = "AllProductsFullAccess is refused: the key it would sign is long-lived and lives in a cluster Secret, because Scaleway has no workload identity federation."
  }
}

variable "crossplane_key_expires_at" {
  description = "RFC 3339 expiry for the Crossplane API key. Null means no expiry. Scaleway has no workload identity federation, so this key is the credential — an expiry is what forces the rotation the factory owns."
  type        = string
  default     = null

  validation {
    condition     = var.crossplane_key_expires_at == null || can(formatdate("YYYY-MM-DD", var.crossplane_key_expires_at))
    error_message = "crossplane_key_expires_at must be an RFC 3339 timestamp, such as 2027-01-01T00:00:00Z."
  }
}

variable "crossplane_allowed_cidrs" {
  description = "Source addresses the Crossplane key may be used from, as an IAM policy condition. Empty derives it from the Public Gateways' egress addresses, which is the only stable source a fully isolated node presents."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.crossplane_allowed_cidrs : can(cidrnetmask(c))])
    error_message = "Every entry must be a valid IPv4 CIDR block."
  }
}

# ---------------------------------------------------------------------------
# Observability — docs/scaleway/cloud-observability.md
# ---------------------------------------------------------------------------

variable "cockpit_token_enabled" {
  description = "Create a query-only Cockpit token so the central observability cluster can federate Scaleway's own metrics and logs. Reading is what the supervision plane does; pushing into Cockpit is billed per sample and is refused."
  type        = bool
  default     = true
}
