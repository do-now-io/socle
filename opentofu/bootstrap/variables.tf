# One module for four clouds. Nothing here names a cloud provider; `cloud`
# picks the artifact's overlay and the operator's cluster type, and that is
# the only thing that differs between EKS, GKE, AKS and Kapsule.
#
# Every variable is typed, every constraint is a validation block with a test
# that trips it, and every default is the position docs/flux-catalog.md argues.

# ---------------------------------------------------------------------------
# Identity of the deployment
# ---------------------------------------------------------------------------

variable "cloud" {
  description = "Which cloud this cluster runs on. Selects the artifact's clusters/<cloud> overlay and the operator's workload identity wiring. Scaleway has no federation the operator knows, so it runs as a plain kubernetes cluster."
  type        = string

  validation {
    condition     = contains(["aws", "gcp", "azure", "scaleway"], var.cloud)
    error_message = "cloud must be one of aws, gcp, azure or scaleway."
  }
}

variable "cluster_name" {
  description = "Cluster this socle serves. Stamped on every object the operator creates, and exposed to the catalog as inputs.cluster.name."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,38}[a-z0-9])?$", var.cluster_name))
    error_message = "cluster_name must be 1 to 40 characters of lowercase letters, digits and dashes, starting with a letter."
  }
}

variable "environment" {
  description = "Environment this cluster serves. Stamped as a label, exposed as inputs.cluster.environment, and the axis the upgrade rings follow."
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

# ---------------------------------------------------------------------------
# The catalog — docs/flux-catalog.md §2 and §3
# ---------------------------------------------------------------------------

# nullable = false on every defaulted variable: a root that groups its
# inputs in an object passes an omitted key as an explicit null, and
# OpenTofu keeps that null unless the variable refuses it. Refusing it is
# what makes the module's default the recommended position for every
# caller.
variable "kube" {
  description = <<-EOT
    The catalog modules this cluster enables and their values, as
    `{ <module> = { <attribute> = <value> } }`. List only what differs from
    the catalog's defaults; an absent module is at its default. Module names
    are snake_case. Typed `any` on purpose: a map(any) refuses two modules with
    different attributes, and an object type silently drops a misspelt
    attribute — the validations below are what makes a typo an error at plan.
    The schema is catalog.tf; the README lists it module by module.
  EOT
  type        = any
  default     = {}
  nullable    = false

  validation {
    condition     = can(keys(var.kube)) && alltrue([for m, v in var.kube : can(keys(v))])
    error_message = "kube must be a map of module name => object of attributes."
  }

  validation {
    condition     = !can(keys(var.kube)) || alltrue([for m in keys(var.kube) : contains(keys(local.catalog), m)])
    error_message = "kube: unknown module(s) ${join(", ", try(setsubtract(keys(var.kube), keys(local.catalog)), ["?"]))}. Catalog: ${join(", ", keys(local.catalog))}."
  }

  validation {
    condition     = !can(keys(var.kube)) || alltrue(flatten([for m, v in var.kube : [for a in try(keys(v), []) : contains(keys(lookup(local.catalog, m, {})), a)]]))
    error_message = "kube: unknown attribute. Allowed per module: ${jsonencode({ for m, d in local.catalog : m => keys(d) })}."
  }

  # Unknown module or attribute names are already refused above; this block
  # ignores them so only one diagnostic fires per mistake. A null catalog
  # default means "any type". `enabled` is covered here too: its catalog
  # default is a bool, so anything but true or false is the wrong kind.
  validation {
    condition = !can(keys(var.kube)) || alltrue(flatten([
      for m, v in var.kube : [
        for a, x in try(v, {}) :
        !contains(keys(lookup(local.catalog, m, {})), a)
        || lookup(local.catalog, m, {})[a] == null
        || lookup(local.json_kinds, substr(jsonencode(x), 0, 1), "number") == lookup(local.json_kinds, substr(jsonencode(lookup(local.catalog, m, {})[a]), 0, 1), "number")
      ]
    ]))
    error_message = "kube: an attribute has the wrong type. Each value must have the type of its catalog default: ${jsonencode({ for m, d in local.catalog : m => { for a, x in d : a => lookup(local.json_kinds, substr(jsonencode(x), 0, 1), "number") } })}."
  }
}

# ---------------------------------------------------------------------------
# What the cluster pulls — docs/flux-catalog.md §3 and §7
# ---------------------------------------------------------------------------

variable "socle_version" {
  description = "Tag of the socle artifact to pull. Null means this module's own version, so that one bump of the module tag moves module and artifact together. Set it only on a dev cluster testing a branch build, together with cosign_identity."
  type        = string
  default     = null

  validation {
    condition     = var.socle_version == null || can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+(-[0-9A-Za-z.-]+)?$", var.socle_version))
    error_message = "socle_version must be a SemVer tag such as 1.4.2 or 0.0.0-feat-x.abc1234. latest, main and other moving heads are refused: a cluster pins a version."
  }
}

variable "artifact_url" {
  description = "OCI repository the socle artifact is pulled from. Override for a mirror; the tag is socle_version."
  type        = string
  default     = "oci://ghcr.io/do-now-io/socle/flux-modules"
  nullable    = false

  validation {
    condition     = startswith(var.artifact_url, "oci://")
    error_message = "artifact_url must start with oci://."
  }
}

variable "artifact_pull_secret" {
  description = "Name of an existing kubernetes.io/dockerconfigjson Secret in flux-system that Flux uses to pull the artifact from a private registry. Empty for a public registry. The Secret is created outside this module — a credential never enters OpenTofu."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.artifact_pull_secret == "" || can(regex("^[a-z0-9]([-a-z0-9.]{0,251}[a-z0-9])?$", var.artifact_pull_secret))
    error_message = "artifact_pull_secret must be empty or a valid Kubernetes Secret name (lowercase RFC 1123 subdomain)."
  }
}

variable "cosign_identity" {
  description = "Keyless identity the artifact's signature must match, as issuer and subject regexes. Defaults to the socle's release workflow on main, so production never consumes a branch build by accident. Override on a dev cluster testing a branch. Null means this default. Verification cannot be disabled."
  type = object({
    issuer  = string
    subject = string
  })
  default = {
    issuer  = "^https://token\\.actions\\.githubusercontent\\.com$"
    subject = "^https://github\\.com/do-now-io/socle/\\.github/workflows/publish-artifact\\.yaml@refs/heads/main$"
  }
  nullable = false

  validation {
    condition     = try(length(var.cosign_identity.issuer) > 0 && length(var.cosign_identity.subject) > 0, false)
    error_message = "cosign_identity needs a non-empty issuer and subject. Verification cannot be turned off."
  }
}

# ---------------------------------------------------------------------------
# Flux itself
# ---------------------------------------------------------------------------

variable "operator_version" {
  description = "Chart version of flux-operator, which is also the operator's own version. Pinned exactly: the operator is pre-1.0 and its minors are not a stable contract."
  type        = string
  default     = "0.60.0"
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.operator_version))
    error_message = "operator_version must be an exact x.y.z version. A range on a pre-1.0 dependency is not a pin."
  }
}

variable "flux_version" {
  description = "Flux version the operator installs and keeps converged. 2.x tracks the latest 2 series; an exact version pins it."
  type        = string
  default     = "2.x"
  nullable    = false

  validation {
    condition     = can(regex("^2(\\.[0-9x]+){0,2}$", var.flux_version))
    error_message = "flux_version must be 2.x, 2.y.x or an exact 2.y.z."
  }
}

variable "flux_components" {
  description = "Flux controllers to install. The image automation pair is absent by default: the socle's version moves through a reviewed tfvars change, not through a controller rewriting tags."
  type        = list(string)
  default = [
    "source-controller",
    "kustomize-controller",
    "helm-controller",
    "notification-controller",
  ]
  nullable = false

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

variable "network_policy" {
  description = "Let the operator install network policies isolating the Flux namespace. On by default; Cilium enforces them on every cloud we ship."
  type        = bool
  default     = true
  nullable    = false
}

variable "instance_size" {
  description = "Resource profile the operator applies to the controllers. Empty is the operator's own default; small, medium and large scale requests and limits together."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = contains(["", "small", "medium", "large"], var.instance_size)
    error_message = "instance_size must be empty, small, medium or large."
  }
}

variable "storage_class" {
  description = "Storage class for the source-controller's artifact cache. Empty uses the cluster default."
  type        = string
  default     = ""
  nullable    = false
}

variable "helm_timeout_seconds" {
  description = "How long to wait for each release to become ready. The instance release is the slow one: its health check waits for the operator to converge the controllers."
  type        = number
  default     = 600
  nullable    = false

  validation {
    condition     = var.helm_timeout_seconds >= 60 && floor(var.helm_timeout_seconds) == var.helm_timeout_seconds
    error_message = "helm_timeout_seconds must be a whole number of seconds, at least 60."
  }
}
