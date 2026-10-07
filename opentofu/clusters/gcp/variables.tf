# The client's whole surface: a version, a cloud block, a catalog block.
# Everything else is the modules' recommended position.

variable "socle_version" {
  description = "The socle release this cluster runs. In a client's copy this variable is also in both module sources (?tag=), so this one line moves foundations, bootstrap and the artifact together."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+(-[0-9A-Za-z.-]+)?$", var.socle_version))
    error_message = "socle_version must be a SemVer tag such as 1.4.2, or a branch pre-release such as 0.0.0-feat-x.abc1234."
  }
}

variable "gcp" {
  description = "The foundations module's inputs, grouped; project_id and region also configure the google provider. Required keys are the ones the module leaves without a default; every other key is optional and passes through as-is."
  type = object({
    project_id                               = string
    region                                   = string
    cluster_name                             = string
    owner                                    = string
    environment                              = string
    maintenance_window                       = object({ start_time = string, end_time = string, recurrence = string })
    project_number                           = optional(string)
    additional_labels                        = optional(map(string))
    network_name                             = optional(string)
    create_network                           = optional(bool)
    create_subnetwork                        = optional(bool)
    subnetwork_name                          = optional(string)
    pod_range_name                           = optional(string)
    node_range_cidr                          = optional(string)
    pod_range_cidr                           = optional(string)
    proxy_only_range_cidr                    = optional(string)
    create_proxy_only_subnet                 = optional(bool)
    create_nat                               = optional(bool)
    subnet_flow_logs_enabled                 = optional(bool)
    enable_private_nodes                     = optional(bool)
    control_plane_ip_endpoints_enabled       = optional(bool)
    control_plane_dns_allow_external_traffic = optional(bool)
    gateway_api_enabled                      = optional(bool)
    release_channel                          = optional(string)
    maintenance_exclusions                   = optional(list(object({ name = string, start_time = string, end_time = string, scope = string })))
    kubernetes_min_version                   = optional(string)
    enable_upgrade_notifications             = optional(bool)
    logging_components                       = optional(list(string))
    monitoring_components                    = optional(list(string))
    cost_allocation_enabled                  = optional(bool)
    backup_agent_enabled                     = optional(bool)
    billing_export_dataset_id                = optional(string)
    billing_export_dataset_location          = optional(string)
    observability_reader_members             = optional(list(string))
    deletion_protection                      = optional(bool)
    crossplane                               = optional(object({ allowed_roles = optional(list(string), []), dns_zones = optional(list(string), []) }))
    gateway_certificate                      = optional(object({ dns_zone = string, domains = list(string) }))
  })
  nullable = false
}

variable "kube" {
  description = "Catalog modules and their values, as { <module> = { <attribute> = <value> } }. Only what differs from the defaults; validated against the catalog by the bootstrap module."
  type        = any
  default     = {}
}

variable "cosign_identity" {
  description = "Override of the signature identity the cluster trusts. Null keeps the bootstrap module's default, the release workflow on main. Set it only on a dev cluster testing a branch build."
  type = object({
    issuer  = string
    subject = string
  })
  default = null
}

variable "artifact_url" {
  description = "Override of the OCI repository the artifact is pulled from, for a mirror. Null keeps the socle registry."
  type        = string
  default     = null
}

variable "artifact_pull_secret" {
  description = "Name of an existing dockerconfigjson Secret in flux-system for a private registry. Empty for a public one; the Secret is created outside OpenTofu."
  type        = string
  default     = ""
}
