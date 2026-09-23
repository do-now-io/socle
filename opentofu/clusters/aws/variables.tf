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

variable "aws" {
  description = "The foundations module's inputs, grouped, plus the region for the aws provider. Required keys are the ones the module leaves without a default; every other key is optional and passes through as-is."
  type = object({
    region                               = string
    cluster_name                         = string
    owner                                = string
    environment                          = string
    availability_zones                   = list(string)
    cluster_endpoint_public_access_cidrs = list(string)
    kubernetes_version                   = string
    additional_tags                      = optional(map(string))
    create_vpc                           = optional(bool)
    vpc_id                               = optional(string)
    private_subnet_ids                   = optional(list(string))
    public_subnet_ids                    = optional(list(string))
    vpc_cidr                             = optional(string)
    create_nat_gateway                   = optional(bool)
    vpc_flow_logs_enabled                = optional(bool)
    secrets_encryption_enabled           = optional(bool)
    secrets_encryption_kms_key_arn       = optional(string)
    cluster_log_types                    = optional(list(string))
    log_retention_days                   = optional(number)
    force_update_version                 = optional(bool)
  })
}

variable "kube" {
  description = "Catalog modules and their values, as { <module> = { <attribute> = <value> } }. Only what differs from the defaults; validated against the catalog by the bootstrap module."
  type        = any
  default     = {}
}

variable "cilium" {
  description = "The socle's Cilium, installed before Flux because EKS is created with no CNI: { enabled = true, hubble = false, gateway_api = true }, every key optional. Only what differs from those defaults; validated by the bootstrap module. enabled = false is for a cluster that brings its own CNI and DNS — the e2e test double, never a real EKS."
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
