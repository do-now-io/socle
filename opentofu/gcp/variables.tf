# Every variable is typed, every constrained value is enforced by a validation
# block rather than by documentation, and every default is the position the
# research documents recommend. Options we would not recommend are absent.

# ---------------------------------------------------------------------------
# Identity of the deployment
# ---------------------------------------------------------------------------

variable "project_id" {
  description = "Google Cloud project that holds the cluster and its network."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid Google Cloud project ID: 6 to 30 characters, lowercase letters, digits and dashes, starting with a letter."
  }
}

variable "region" {
  description = "Region of the cluster and its subnetwork. The cluster is regional; zonal clusters are not offered."
  type        = string

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))
    error_message = "region must be a Google Cloud region such as europe-west1, not a zone."
  }
}

variable "cluster_name" {
  description = "Name of the GKE cluster. Also prefixes the network resources the module creates."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,38}[a-z0-9])?$", var.cluster_name))
    error_message = "cluster_name must be 1 to 40 characters of lowercase letters, digits and dashes, starting with a letter."
  }
}

variable "owner" {
  description = "Team accountable for the cluster. Stamped as a label on every billable resource."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9_-]{1,63}$", var.owner))
    error_message = "owner must be a valid label value: 1 to 63 characters of lowercase letters, digits, dashes and underscores."
  }
}

variable "environment" {
  description = "Environment this cluster serves. Stamped as a label, and the axis the upgrade ring order follows."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of dev, staging or prod."
  }
}

variable "additional_labels" {
  description = "Extra labels merged onto the standard set. Cannot override owner, environment or socle-version."
  type        = map(string)
  default     = {}

  validation {
    condition     = length(setintersection(keys(var.additional_labels), ["owner", "environment", "socle-version"])) == 0
    error_message = "additional_labels must not contain owner, environment or socle-version — those are the standard label set."
  }
}

# ---------------------------------------------------------------------------
# Network — docs/gcp/network-security.md
# ---------------------------------------------------------------------------

variable "network_name" {
  description = "Name of an existing custom-mode VPC to attach the cluster to. Mutually exclusive with create_network."
  type        = string
  default     = null

  validation {
    condition     = var.create_network != (var.network_name != null)
    error_message = "Set network_name to attach to an existing VPC, or create_network to have the module build one — exactly one of the two."
  }
}

variable "create_network" {
  description = "Create the VPC instead of using an existing one. The common case is a network the consumer already owns."
  type        = bool
  default     = false
}

variable "create_subnetwork" {
  description = "Create the cluster subnetwork. Set to false in a Shared VPC where the network team owns subnets, and supply subnetwork_name and pod_range_name instead."
  type        = bool
  default     = true
}

variable "subnetwork_name" {
  description = "Name of an existing subnetwork in var.region to place the cluster in. Required when create_subnetwork is false, ignored otherwise."
  type        = string
  default     = null

  validation {
    condition     = var.create_subnetwork || var.subnetwork_name != null
    error_message = "subnetwork_name is required when create_subnetwork is false."
  }
}

variable "pod_range_name" {
  description = "Name of the secondary range that carries Pod addresses. Defaults to <cluster_name>-pods, which is what the module creates; set it when attaching to a subnetwork someone else owns."
  type        = string
  default     = null

  validation {
    condition     = var.create_subnetwork || var.pod_range_name != null
    error_message = "pod_range_name is required when create_subnetwork is false: the module cannot guess the name of a range it does not own."
  }
}

variable "node_range_cidr" {
  description = "Primary range of the cluster subnetwork, used by nodes and by internal load balancers."
  type        = string
  default     = "10.0.0.0/24"

  validation {
    condition     = can(cidrnetmask(var.node_range_cidr))
    error_message = "node_range_cidr must be a valid IPv4 CIDR block."
  }
}

variable "pod_range_cidr" {
  description = "Secondary range for Pod addresses. Autopilot fixes 32 Pods per node, so a /26 is consumed per node: a /17 carries 512 nodes."
  type        = string
  default     = "10.4.0.0/17"

  validation {
    condition     = can(cidrnetmask(var.pod_range_cidr)) && tonumber(split("/", var.pod_range_cidr)[1]) <= 17
    error_message = "pod_range_cidr must be a valid IPv4 CIDR of /17 or larger, which is 512 Autopilot nodes."
  }
}

# The Services range is deliberately absent: GKE assigns Service addresses
# from its own managed range on Autopilot 1.27 and later, so there is nothing
# to size or to collide with.

variable "proxy_only_range_cidr" {
  description = "Range of the REGIONAL_MANAGED_PROXY subnetwork. Regional Application Load Balancers, and therefore Gateways, cannot exist without it."
  type        = string
  default     = "10.8.0.0/23"

  validation {
    condition     = can(cidrnetmask(var.proxy_only_range_cidr)) && tonumber(split("/", var.proxy_only_range_cidr)[1]) <= 26
    error_message = "proxy_only_range_cidr must be a valid IPv4 CIDR of /26 or larger — /26 is the load balancer's hard minimum, /23 is the recommendation."
  }
}

variable "create_proxy_only_subnet" {
  description = "Create the proxy-only subnetwork. Set to false when another cluster in the same region and VPC already created it — the pool is shared."
  type        = bool
  default     = true
}

variable "create_nat" {
  description = "Create a Cloud Router and Cloud NAT for egress. A cluster with private nodes and no NAT cannot pull an image from outside Google Cloud."
  type        = bool
  default     = true

  # Failing here is kinder than failing at the first ImagePullBackOff. A
  # subnetwork the module does not own may already have egress of its own,
  # which is the one case where private nodes without NAT is coherent.
  validation {
    condition     = !var.enable_private_nodes || var.create_nat || !var.create_subnetwork
    error_message = "Private nodes need egress: either let the module create Cloud NAT, or attach to a subnetwork whose egress someone else already provides."
  }
}

variable "subnet_flow_logs_enabled" {
  description = "Enable VPC flow logs on the cluster subnetwork, at half sampling over ten-minute windows. Vended network logs are billed at $0.25/GiB, which is a dollar or so a month at that sampling for a socle cluster."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Control plane access — docs/gcp/network-security.md
# ---------------------------------------------------------------------------

variable "enable_private_nodes" {
  description = "Nodes get no external address. Flips the Autopilot default, which is public."
  type        = bool
  default     = true
}

variable "control_plane_ip_endpoints_enabled" {
  description = "Expose the control plane on IP endpoints. Off: the DNS-based endpoint replaces them, and with it the authorized-networks maintenance problem."
  type        = bool
  default     = false
}

variable "control_plane_dns_allow_external_traffic" {
  description = "Allow user traffic to the DNS-based control plane endpoint. True means the control plane is reachable wherever Google Cloud APIs are, gated by IAM; VPC Service Controls is the network boundary and is set outside this module."
  type        = bool
  default     = true
}

# master_authorized_networks is absent by decision: it only applies to the IP
# endpoints this module disables, and it has to be rewritten every time a
# consumer's subnet or CI runner address changes.

# ---------------------------------------------------------------------------
# Upgrades — docs/gcp/managed-scope.md
# ---------------------------------------------------------------------------

variable "release_channel" {
  description = "GKE release channel. REGULAR is Google's recommendation and the estate-wide default; RAPID is outside the GKE SLA and belongs in pre-production only."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be RAPID, REGULAR or STABLE. EXTENDED is rejected: Google does not allow Autopilot clusters in the Extended channel."
  }
}

variable "maintenance_window" {
  description = <<-EOT
    When GKE may touch this cluster. Required on purpose — a silent default
    would mean nobody decided when production gets upgraded, and the day of
    the week is what orders a dev/staging/prod ring.

    start_time and end_time are RFC3339 timestamps whose difference is the
    window length; recurrence is an RFC5545 RRULE. At least 48 hours of
    maintenance availability must remain in any 92-day rolling window, and
    only contiguous blocks of four hours or more count.
  EOT
  type = object({
    start_time = string
    end_time   = string
    recurrence = string
  })

  validation {
    condition = (
      can(formatdate("YYYY-MM-DD", var.maintenance_window.start_time)) &&
      can(formatdate("YYYY-MM-DD", var.maintenance_window.end_time))
    )
    error_message = "maintenance_window start_time and end_time must be RFC3339 timestamps, for example 2026-01-05T02:00:00Z."
  }

  validation {
    condition = (
      timecmp(var.maintenance_window.end_time, timeadd(var.maintenance_window.start_time, "4h")) >= 0
    )
    error_message = "maintenance_window must be at least 4 hours long: shorter blocks do not count towards GKE's 48-hour availability requirement."
  }

  validation {
    condition     = can(regex("FREQ=(DAILY|WEEKLY)", var.maintenance_window.recurrence))
    error_message = "maintenance_window recurrence must be an RRULE with FREQ=DAILY or FREQ=WEEKLY, for example FREQ=WEEKLY;BYDAY=SA."
  }
}

variable "maintenance_exclusions" {
  description = "Windows during which GKE must not upgrade the cluster. The brake, not the routine: empty by default."
  type = list(object({
    name       = string
    start_time = string
    end_time   = string
    scope      = string
  }))
  default = []

  validation {
    condition = alltrue([
      for e in var.maintenance_exclusions :
      contains(["NO_UPGRADES", "NO_MINOR_UPGRADES", "NO_MINOR_OR_NODE_UPGRADES"], e.scope)
    ])
    error_message = "Each exclusion scope must be NO_UPGRADES, NO_MINOR_UPGRADES or NO_MINOR_OR_NODE_UPGRADES."
  }

  validation {
    condition = alltrue([
      for e in var.maintenance_exclusions :
      e.scope != "NO_UPGRADES" || timecmp(e.end_time, timeadd(e.start_time, "2160h")) <= 0
    ])
    error_message = "A NO_UPGRADES exclusion cannot exceed 90 days, and Google recommends staying under 30."
  }

  validation {
    condition = length([
      for e in var.maintenance_exclusions : e if e.scope == "NO_UPGRADES"
    ]) <= 3
    error_message = "GKE accepts at most three exclusions with the NO_UPGRADES scope."
  }

  validation {
    condition     = length(var.maintenance_exclusions) <= 20
    error_message = "GKE accepts at most 20 maintenance exclusions per cluster."
  }
}

variable "kubernetes_min_version" {
  description = "Floor for the control plane version. Raise-only escape hatch for promoting a minor deliberately; leave null in steady state and let the channel decide."
  type        = string
  default     = null
}

variable "enable_upgrade_notifications" {
  description = "Create a Pub/Sub topic and publish cluster upgrade notifications to it, so automation can react instead of polling."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Observability and cost — docs/gcp/managed-scope.md, docs/gcp/cloud-observability.md
# ---------------------------------------------------------------------------

variable "logging_components" {
  description = "GKE log sources to send to Cloud Logging. SYSTEM_COMPONENTS cannot be removed; drop WORKLOADS when application logs are collected in-cluster."
  type        = list(string)
  default     = ["SYSTEM_COMPONENTS", "WORKLOADS"]

  validation {
    condition     = contains(var.logging_components, "SYSTEM_COMPONENTS")
    error_message = "logging_components must include SYSTEM_COMPONENTS."
  }

  validation {
    condition = alltrue([
      for c in var.logging_components :
      contains(["SYSTEM_COMPONENTS", "WORKLOADS", "APISERVER", "SCHEDULER", "CONTROLLER_MANAGER", "KCP_VPA"], c)
    ])
    error_message = "logging_components accepts SYSTEM_COMPONENTS, WORKLOADS, APISERVER, SCHEDULER, CONTROLLER_MANAGER and KCP_VPA."
  }
}

variable "monitoring_components" {
  description = "GKE metric sources. SYSTEM_COMPONENTS is free and mandatory; every other component is billed per sample, so none is defaulted on."
  type        = list(string)
  default     = ["SYSTEM_COMPONENTS"]

  validation {
    condition     = contains(var.monitoring_components, "SYSTEM_COMPONENTS")
    error_message = "monitoring_components must include SYSTEM_COMPONENTS."
  }

  validation {
    condition = alltrue([
      for c in var.monitoring_components :
      contains([
        "SYSTEM_COMPONENTS", "APISERVER", "SCHEDULER", "CONTROLLER_MANAGER", "STORAGE",
        "HPA", "POD", "DAEMONSET", "DEPLOYMENT", "STATEFULSET", "KUBELET", "CADVISOR",
        "DCGM", "JOBSET",
      ], c)
    ])
    error_message = "monitoring_components contains a component GKE does not expose; see the cluster's monitoring_config documentation."
  }
}

# GKE Auto-Monitoring is absent by decision: the feature is free, the samples
# it starts ingesting are not.

variable "cost_allocation_enabled" {
  description = "Add cluster, namespace and workload labels to the detailed billing export. On from day one because it does not backfill."
  type        = bool
  default     = true
}

variable "backup_agent_enabled" {
  description = "Install the Backup for GKE agent. Off by default: $9 per protected namespace per month, where Velero covers a Persistent-Disk-backed socle for a third of that."
  type        = bool
  default     = false
}

variable "billing_export_dataset_id" {
  description = "When set, create a BigQuery dataset to receive the detailed billing export. Linking the billing account to it stays a Console step — Google exposes no API for it."
  type        = string
  default     = null
}

variable "billing_export_dataset_location" {
  description = "Location of the billing export dataset. Ignored when billing_export_dataset_id is null."
  type        = string
  default     = "EU"
}

variable "observability_reader_members" {
  description = "Principals granted read-only access to this project's metrics — the central observability cluster's federated identity, never a key."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for m in var.observability_reader_members :
      can(regex("^(serviceAccount|group|user|principal|principalSet):", m))
    ])
    error_message = "Each member must be a fully qualified IAM principal, such as serviceAccount:reader@project.iam.gserviceaccount.com."
  }
}

# ---------------------------------------------------------------------------
# Identities — docs/gcp/managed-scope.md
# ---------------------------------------------------------------------------

# Workload Identity Federation has no variable: Autopilot pre-configures it and
# it cannot be disabled. The pool is exposed as an output.

variable "crossplane_service_account_namespace" {
  description = "Namespace of the Crossplane GCP provider's Kubernetes service account."
  type        = string
  default     = "crossplane-system"
}

variable "crossplane_service_account_name" {
  description = "Name of the Crossplane GCP provider's Kubernetes service account. Must match the socle's DeploymentRuntimeConfig — the provider Pod's service account name is not stable across provider revisions unless it is pinned there."
  type        = string
  default     = "provider-gcp"
}

variable "crossplane_project_roles" {
  description = "Project roles granted to the identity the in-cluster Crossplane provider assumes. Empty by default: the catalog does not exist yet, and a list written today would be a guess."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for r in var.crossplane_project_roles :
      can(regex("^(roles/|projects/[^/]+/roles/|organizations/[0-9]+/roles/)", r))
    ])
    error_message = "Each role must be a role name such as roles/cloudsql.admin or a fully qualified custom role."
  }
}

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

variable "deletion_protection" {
  description = "Refuse to destroy the cluster. On by default; test fixtures turn it off."
  type        = bool
  default     = true
}
