# One module for four clouds. Nothing here names a provider: what differs
# between EKS, GKE, AKS and Kapsule is a single enum, cluster_type, which the
# operator uses to wire cloud-specific workload identity.
#
# Every variable is typed, every constrained value carries a validation block,
# and every default is the position docs/flux-bootstrap.md argues for.

# ---------------------------------------------------------------------------
# Identity of the deployment
# ---------------------------------------------------------------------------

variable "cluster_name" {
  description = "Cluster this Flux instance serves. Stamped on every object the operator creates, so a fleet-wide query can tell them apart."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,38}[a-z0-9])?$", var.cluster_name))
    error_message = "cluster_name must be 1 to 40 characters of lowercase letters, digits and dashes, starting with a letter."
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

variable "owner" {
  description = "Team accountable for the cluster. Stamped as a label on every object."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9_-]{1,63}$", var.owner))
    error_message = "owner must be 1 to 63 characters of lowercase letters, digits, dashes and underscores."
  }
}

variable "cluster_type" {
  description = "Which cloud this runs on. The operator uses it to wire workload identity for the controllers: aws, azure and gcp have federated identity, kubernetes covers Scaleway and anything else."
  type        = string
  default     = "kubernetes"

  validation {
    condition     = contains(["kubernetes", "aws", "azure", "gcp", "openshift"], var.cluster_type)
    error_message = "cluster_type must be one of kubernetes, aws, azure, gcp or openshift. Scaleway has no workload identity federation, so it is kubernetes."
  }
}

# ---------------------------------------------------------------------------
# Versions — docs/flux-bootstrap.md
# ---------------------------------------------------------------------------

variable "operator_version" {
  description = "Chart version of flux-operator, which is also the operator's own version. Pinned exactly: the operator is pre-1.0 and its minors are not a stable contract."
  type        = string
  default     = "0.60.0"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.operator_version))
    error_message = "operator_version must be an exact x.y.z version. A range on a pre-1.0 dependency is not a pin."
  }
}

variable "flux_version" {
  description = "Flux version the operator installs and keeps converged. \"2.x\" tracks the latest 2 series; an exact version pins it."
  type        = string
  default     = "2.x"

  validation {
    condition     = can(regex("^2(\\.[0-9x]+){0,2}$", var.flux_version))
    error_message = "flux_version must be 2.x, 2.y.x or an exact 2.y.z."
  }
}

variable "flux_components" {
  description = "Flux controllers to install. The image automation pair is absent by default: the socle's version moves through Git, not through a controller rewriting tags in the cluster."
  type        = list(string)
  default = [
    "source-controller",
    "kustomize-controller",
    "helm-controller",
    "notification-controller",
  ]

  validation {
    condition = alltrue([for c in var.flux_components : contains([
      "source-controller",
      "kustomize-controller",
      "helm-controller",
      "notification-controller",
      "image-reflector-controller",
      "image-automation-controller",
      "source-watcher",
    ], c)])
    error_message = "flux_components must be drawn from the controllers the operator knows."
  }

  validation {
    condition     = contains(var.flux_components, "source-controller") && contains(var.flux_components, "kustomize-controller")
    error_message = "source-controller and kustomize-controller are the reconciliation path itself — an instance without them syncs nothing."
  }
}

# ---------------------------------------------------------------------------
# What the cluster pulls — docs/flux-bootstrap.md
# ---------------------------------------------------------------------------

variable "sync_url" {
  description = "Where the cluster pulls the socle from. An oci:// artifact by default — the socle is distributed as one signed OCI artifact, not as a Git repository per client."
  type        = string

  validation {
    condition     = can(regex("^(oci|https|ssh)://", var.sync_url))
    error_message = "sync_url must start with oci://, https:// or ssh://."
  }
}

variable "sync_kind" {
  description = "Source kind the operator creates for the root sync. OCIRepository matches the socle's distribution; GitRepository exists for a client who insists on a repository."
  type        = string
  default     = "OCIRepository"

  validation {
    condition     = contains(["OCIRepository", "GitRepository", "Bucket"], var.sync_kind)
    error_message = "sync_kind must be OCIRepository, GitRepository or Bucket."
  }

  validation {
    condition     = var.sync_kind != "OCIRepository" || startswith(var.sync_url, "oci://")
    error_message = "An OCIRepository sync needs an oci:// URL."
  }
}

variable "sync_ref" {
  description = "The tag, digest or branch to pin. Required with no default: a floating reference would make \"which version is deployed\" unanswerable, which is the one question the distribution exists to answer."
  type        = string

  validation {
    condition     = length(var.sync_ref) > 0
    error_message = "sync_ref must name a tag, a digest or a branch."
  }

  validation {
    condition     = !contains(["latest", "main", "master", "HEAD"], var.sync_ref)
    error_message = "latest, main, master and HEAD are refused: a cluster must pin a version, not follow a moving head."
  }
}

variable "sync_path" {
  description = "Path inside the artifact the root Kustomization builds."
  type        = string
  default     = "."
}

variable "sync_interval" {
  description = "How often the root source is checked. One minute is the operator's own default and costs one registry HEAD request."
  type        = string
  default     = "1m"

  validation {
    condition     = can(regex("^([0-9]+(\\.[0-9]+)?(ms|s|m|h))+$", var.sync_interval))
    error_message = "sync_interval must be a Go duration, such as 1m or 30s."
  }
}

variable "sync_pull_secret" {
  description = "Name of an existing Kubernetes secret holding registry credentials for the artifact. Empty means the registry is public or the node identity is enough."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Supply chain — docs/flux-bootstrap.md#cosign
# ---------------------------------------------------------------------------

variable "cosign_verification_enabled" {
  description = "Patch the root OCIRepository so Flux verifies the artifact's cosign signature before applying it. The FluxInstance sync spec has no verify field of its own, so this goes through a kustomize patch."
  type        = bool
  default     = true

  validation {
    condition     = !var.cosign_verification_enabled || var.sync_kind == "OCIRepository"
    error_message = "cosign verification only applies to an OCIRepository sync."
  }
}

variable "cosign_identity" {
  description = "Keyless identity the signature must match, as an object of issuer and subject regexes. Null verifies the signature without pinning who produced it, which is weaker and should be temporary."
  type = object({
    issuer  = string
    subject = string
  })
  default = null

  validation {
    condition     = var.cosign_identity == null || try(length(var.cosign_identity.issuer) > 0 && length(var.cosign_identity.subject) > 0, false)
    error_message = "cosign_identity needs a non-empty issuer and subject, or must be null."
  }
}

# ---------------------------------------------------------------------------
# Cluster shape
# ---------------------------------------------------------------------------

variable "namespace" {
  description = "Namespace holding the operator and the Flux controllers."
  type        = string
  default     = "flux-system"
}

variable "network_policy" {
  description = "Let the operator install network policies isolating the Flux namespace. On by default; Cilium and Dataplane V2 both enforce them."
  type        = bool
  default     = true
}

variable "multitenant" {
  description = "Lock cross-namespace source references, so a tenant Kustomization cannot reference another tenant's source. Off until the catalog states what it needs."
  type        = bool
  default     = false
}

variable "storage_class" {
  description = "Storage class for the source-controller's artifact cache. Empty uses the cluster default."
  type        = string
  default     = ""
}

variable "instance_size" {
  description = "Resource profile the operator applies to the controllers. Empty is the operator's own default; small, medium and large scale requests and limits together."
  type        = string
  default     = ""

  validation {
    condition     = contains(["", "small", "medium", "large"], var.instance_size)
    error_message = "instance_size must be empty, small, medium or large."
  }
}

variable "helm_timeout_seconds" {
  description = "How long to wait for each release to become ready. The operator reconciles the Flux controllers after its own install, so the instance release is the slow one."
  type        = number
  default     = 600

  validation {
    condition     = var.helm_timeout_seconds >= 60 && floor(var.helm_timeout_seconds) == var.helm_timeout_seconds
    error_message = "helm_timeout_seconds must be a whole number of seconds, at least 60."
  }
}
