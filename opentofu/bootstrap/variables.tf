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

variable "region" {
  description = "Region the cluster runs in, exposed to the catalog as inputs.cluster.region. Regional cloud APIs need it — on AWS the Pod Identity associations the crossplane module creates. Empty when the caller does not know it; a module that needs it says so."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.region == "" || can(regex("^[a-z0-9-]{2,32}$", var.region))
    error_message = "region must be empty or a cloud region name in lowercase, such as eu-west-3, europe-west1, westeurope or fr-par."
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

  validation {
    condition     = !can(keys(var.kube)) || alltrue([for m in keys(var.kube) : !contains(keys(local.catalog), m) || contains(lookup(local.catalog_clouds, m, [var.cloud]), var.cloud)])
    error_message = "kube: a module is not offered on ${var.cloud}. Cloud-bound modules: ${jsonencode(local.catalog_clouds)}."
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

  # values is free-form on purpose, minus one rule: no secret material. What a
  # client writes there ends up in the OpenTofu state and in a ConfigMap on
  # the cluster. The crossplane chart takes no credential of its own; the two
  # places one could still be smuggled in are refused: a Secret among
  # extraObjects, and an environment variable whose name says it carries one.
  # Those go through values_secret instead.
  validation {
    condition = (
      !can(var.kube.crossplane.values)
      || !can(keys(var.kube.crossplane.values))
      || (
        !anytrue(try([for o in var.kube.crossplane.values.extraObjects : try(o.kind == "Secret", false)], []))
        && !anytrue(flatten([
          for e in ["extraEnvVarsCrossplane", "extraEnvVarsCrossplaneInit", "extraEnvVarsRBACManager"] : [
            for k in try(keys(var.kube.crossplane.values[e]), []) :
            can(regex("(?i)(password|passwd|secret|token|credential|private_?key|api_?key|access_?key)", k))
          ]
        ]))
      )
    )
    error_message = "kube.crossplane.values must not carry secrets: a Secret in extraObjects, and an extraEnvVars* entry named like a password, token, secret, credential or key, are refused. Put them in a Secret in crossplane-system and name it in kube.crossplane.values_secret."
  }

  # The root wires it from the foundations' output; a client who writes it
  # himself must write an IAM policy ARN.
  validation {
    condition     = !can(var.kube.crossplane.permissions_boundary) || try(var.kube.crossplane.permissions_boundary == "" || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:policy/.+$", var.kube.crossplane.permissions_boundary)), true)
    error_message = "kube.crossplane.permissions_boundary must be empty or an IAM policy ARN, such as arn:aws:iam::123456789012:policy/socle/acme-prod/crossplane-boundary."
  }

  validation {
    condition     = !can(var.kube.crossplane.values_secret) || try(var.kube.crossplane.values_secret == "" || can(regex("^[a-z0-9]([-a-z0-9.]{0,251}[a-z0-9])?$", var.kube.crossplane.values_secret)), true)
    error_message = "kube.crossplane.values_secret must be empty or a valid Kubernetes Secret name (lowercase RFC 1123 subdomain)."
  }
  # --- external_dns — docs/catalog/external-dns.md -------------------------
  # Per-attribute rules. They read var.kube with the catalog default as the
  # fallback — not local.modules, which depends on var.kube and would be a
  # cycle — so a client who writes only `enabled = true` is told what else is
  # missing. Each is guarded so an unknown module or attribute, refused above,
  # does not also fire here.

  validation {
    condition     = !can(keys(var.kube)) || !try(var.kube.external_dns.enabled, false) || length(try(var.kube.external_dns.domain_filters, [])) > 0
    error_message = "kube.external_dns: domain_filters must name at least one zone when the module is enabled. external-dns publishes nothing outside its filters, so an empty list is a module that does nothing."
  }

  validation {
    condition     = !can(keys(var.kube)) || alltrue([for d in try(var.kube.external_dns.domain_filters, []) : can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}\\.?$", d))])
    error_message = "kube.external_dns: every domain_filters entry must be a DNS name such as acme.example, lowercase, without a leading dot or a wildcard."
  }

  validation {
    condition     = !can(keys(var.kube)) || contains(["upsert-only", "sync"], try(var.kube.external_dns.policy, "upsert-only"))
    error_message = "kube.external_dns.policy must be upsert-only (never deletes a record: the safe default) or sync (also deletes what it owns)."
  }


  validation {
    condition     = !can(keys(var.kube)) || can(regex("^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$", try(var.kube.external_dns.txt_owner_id, "x")))
    error_message = "kube.external_dns.txt_owner_id must be 1 to 63 characters of letters, digits, dots, dashes and underscores: it is written into every TXT record the module owns."
  }
  validation {
    condition = (
      !can(var.kube.external_dns.values)
      || !can(keys(var.kube.external_dns.values))
      || (
        !can(var.kube.external_dns.values.secretConfiguration)
        && alltrue([
          for e in concat(try(tolist(var.kube.external_dns.values.env), []), try(tolist(var.kube.external_dns.values.provider.webhook.env), [])) :
          !(can(e.value) && can(regex("(?i)(secret|password|passwd|token|api_?key|access_?key|private_?key)", try(e.name, ""))))
        ])
        && alltrue([
          for a in concat(
            try(keys(var.kube.external_dns.values.extraArgs), []),
            try([for x in tolist(var.kube.external_dns.values.extraArgs) : tostring(x)], []),
          ) :
          !can(regex("(?i)(secret|password|passwd|token|api-?key|aes-key|private-?key)", a))
        ])
      )
    )
    error_message = "kube.external_dns.values must not carry secrets: secretConfiguration, an env entry with a literal value whose name looks like a credential (AWS_SECRET_ACCESS_KEY, SCW_SECRET_KEY, …), and an extraArgs flag such as txt-encrypt-aes-key are refused. Put them in a Secret in the external-dns namespace and name it in kube.external_dns.values_secret."
  }
  validation {
    condition     = !can(var.kube.external_dns.values_secret) || try(var.kube.external_dns.values_secret == "" || can(regex("^[a-z0-9]([-a-z0-9.]{0,251}[a-z0-9])?$", var.kube.external_dns.values_secret)), true)
    error_message = "kube.external_dns.values_secret must be empty or a valid Kubernetes Secret name (lowercase RFC 1123 subdomain)."
  }
  validation {
    condition = (
      !can(var.kube.argocd.domain)
      || lookup(local.json_kinds, substr(jsonencode(var.kube.argocd.domain), 0, 1), "number") != "string"
      || var.kube.argocd.domain == ""
      || can(regex("^([a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", var.kube.argocd.domain))
    )
    error_message = "kube.argocd.domain must be empty or a fully qualified DNS name in lowercase, such as argocd.acme.example: no scheme, no port, no path."
  }

  # values is free-form on purpose, minus one rule: no secret material. What a
  # client writes there ends up in the OpenTofu state and in a ConfigMap on
  # the cluster; the chart's secret-bearing paths are refused so that a
  # private key or a password has to go through values_secret instead.
  validation {
    condition = (
      !can(var.kube.argocd.values)
      || !can(keys(var.kube.argocd.values))
      || (
        !can(var.kube.argocd.values.configs.secret)
        && !can(var.kube.argocd.values.configs.credentialTemplates)
        && !can(var.kube.argocd.values.configs.clusterCredentials)
        && alltrue([
          for r in try(values(var.kube.argocd.values.configs.repositories), []) :
          !anytrue([for k in ["password", "sshPrivateKey", "githubAppPrivateKey", "bearerToken", "tlsClientCertData", "tlsClientCertKey"] : can(r[k])])
        ])
      )
    )
    error_message = "kube.argocd.values must not carry secrets: configs.secret, configs.credentialTemplates, configs.clusterCredentials and a password, key or token under configs.repositories are refused. Put them in a Secret in the argocd namespace and name it in kube.argocd.values_secret."
  }

  validation {
    condition     = !can(var.kube.argocd.values_secret) || try(var.kube.argocd.values_secret == "" || can(regex("^[a-z0-9]([-a-z0-9.]{0,251}[a-z0-9])?$", var.kube.argocd.values_secret)), true)
    error_message = "kube.argocd.values_secret must be empty or a valid Kubernetes Secret name (lowercase RFC 1123 subdomain)."
  }
}

# ---------------------------------------------------------------------------
# Cilium — cilium.tf and docs/catalog/cilium.md
# ---------------------------------------------------------------------------

variable "cilium" {
  description = <<-EOT
    The socle's Cilium, on the clouds whose foundations create a cluster with
    no CNI — aws and azure — as `{ enabled, hubble, gateway_api }`, every key
    optional: `enabled` (true) installs it before Flux; false means the
    cluster brings its own CNI and DNS, which only a test double does.
    `hubble` (false) adds Hubble Relay and UI. `gateway_api` (true) makes
    Cilium serve the `cilium` GatewayClass. `values` ({}) is any Cilium chart
    value, merged over the socle's so the client wins; private keys are
    refused there, and the chart's `existingSecret` fields name a Secret
    instead. Refused on gcp and scaleway, where the cloud operates Cilium.
    Typed `any` and validated like `kube`, so a misspelt key is an error at
    plan. Chart versions are pinned in cilium.tf.
  EOT
  type        = any
  default     = {}
  nullable    = false

  validation {
    condition     = can(keys(var.cilium))
    error_message = "cilium must be an object of attributes."
  }

  validation {
    condition     = !can(keys(var.cilium)) || alltrue([for a in keys(var.cilium) : contains(keys(local.cilium_schema), a)])
    error_message = "cilium: unknown attribute. Allowed: ${join(", ", keys(local.cilium_schema))}."
  }

  validation {
    condition = !can(keys(var.cilium)) || alltrue([
      for a, x in var.cilium :
      !contains(keys(local.cilium_schema), a)
      || lookup(local.json_kinds, substr(jsonencode(x), 0, 1), "number") == lookup(local.json_kinds, substr(jsonencode(local.cilium_schema[a]), 0, 1), "number")
    ])
    error_message = "cilium: an attribute has the wrong type. Each value must have the type of its default: ${jsonencode({ for a, x in local.cilium_schema : a => lookup(local.json_kinds, substr(jsonencode(x), 0, 1), "number") })}."
  }

  validation {
    condition     = !can(keys(var.cilium)) || contains(local.cilium_clouds, var.cloud) || length(keys(var.cilium)) == 0
    error_message = "cilium is only configurable on ${join(" and ", local.cilium_clouds)}: on gcp (Dataplane V2) and scaleway (Kapsule) the cloud operates Cilium, and the socle installs nothing."
  }

  # values is free-form on purpose, minus one rule: no private key. A
  # helm_release's values land in the OpenTofu state. These are the chart's
  # (1.20.2) paths that take key material inline; each has a Secret-by-name
  # alternative: `existingSecret` beside every Hubble TLS block, a `cilium-ca`
  # Secret created before the apply (or `*.tls.auto.method = certmanager`),
  # and clustermesh.config.enabled = false with the client's own
  # `cilium-clustermesh` Secret.
  validation {
    condition = (
      !can(var.cilium.values)
      || !can(keys(var.cilium.values))
      || (
        !can(var.cilium.values.tls.ca.key)
        && !can(var.cilium.values.hubble.tls.server.key)
        && !can(var.cilium.values.hubble.relay.tls.client.key)
        && !can(var.cilium.values.hubble.relay.tls.server.key)
        && !can(var.cilium.values.hubble.ui.tls.client.key)
        && !can(var.cilium.values.hubble.metrics.tls.server.key)
        && alltrue([
          for c in try(values(var.cilium.values.clustermesh.config.clusters), var.cilium.values.clustermesh.config.clusters, []) :
          !can(c.tls.key)
        ])
      )
    )
    error_message = "cilium.values must not carry private keys: tls.ca.key, hubble.{tls.server,relay.tls.client,relay.tls.server,ui.tls.client,metrics.tls.server}.key and clustermesh.config.clusters[*].tls.key are refused — they would land in the OpenTofu state. Create the Secret in kube-system and name it: the Hubble blocks' existingSecret, a cilium-ca Secret, or clustermesh.config.enabled = false with your own cilium-clustermesh Secret."
  }
}

variable "coredns" {
  description = <<-EOT
    The CoreDNS the socle installs on aws, right after Cilium, as
    `{ values }`: `values` ({}) is any CoreDNS chart value, merged over the
    socle's so the client wins — extra zones, forwarders, plugins. The chart
    has no value that takes secret material inline; a Secret is mounted by
    name through `extraSecrets`, or read through `env[].valueFrom`. Refused
    where the socle installs no CoreDNS: every cloud but aws, and aws with
    cilium.enabled = false. Chart version pinned in cilium.tf.
  EOT
  type        = any
  default     = {}
  nullable    = false

  validation {
    condition     = can(keys(var.coredns))
    error_message = "coredns must be an object of attributes."
  }

  validation {
    condition     = !can(keys(var.coredns)) || alltrue([for a in keys(var.coredns) : contains(keys(local.coredns_schema), a)])
    error_message = "coredns: unknown attribute. Allowed: ${join(", ", keys(local.coredns_schema))}."
  }

  validation {
    condition = !can(keys(var.coredns)) || alltrue([
      for a, x in var.coredns :
      !contains(keys(local.coredns_schema), a)
      || lookup(local.json_kinds, substr(jsonencode(x), 0, 1), "number") == lookup(local.json_kinds, substr(jsonencode(local.coredns_schema[a]), 0, 1), "number")
    ])
    error_message = "coredns: an attribute has the wrong type. Each value must have the type of its default: ${jsonencode({ for a, x in local.coredns_schema : a => lookup(local.json_kinds, substr(jsonencode(x), 0, 1), "number") })}."
  }

  validation {
    condition     = !can(keys(var.coredns)) || length(keys(var.coredns)) == 0 || local.coredns_installed
    error_message = "coredns is only configurable where the socle installs it: aws, with cilium.enabled. AKS, GKE and Kapsule ship their own CoreDNS."
  }
}

variable "cluster_network" {
  description = <<-EOT
    What Cilium needs to know about the cluster, from the foundations'
    outputs, never from the client: `api_endpoint`, the API server as EKS
    returns it (https://host) or AKS does (a bare FQDN), for kube-proxy
    replacement; `service_cidr`, the service range, whose `.10` is CoreDNS's
    address on aws; `pod_cidr`, Cilium's pool on azure, where the VNet holds
    nodes only. Required wherever the socle installs Cilium, ignored
    elsewhere.
  EOT
  type = object({
    api_endpoint = string
    service_cidr = optional(string)
    pod_cidr     = optional(string)
  })
  default = null

  validation {
    condition     = !local.cilium_installed || var.cluster_network != null
    error_message = "cluster_network is required where the socle installs Cilium (aws, azure): pass the foundations' cluster_endpoint as api_endpoint, and service_cidr (aws) or pod_cidr (azure)."
  }

  validation {
    condition     = !(local.cilium_installed && var.cloud == "aws") || try(var.cluster_network.service_cidr != null, false)
    error_message = "cluster_network.service_cidr is required on aws: CoreDNS takes the .10 address of the service range, the one every node's kubelet is told to use."
  }

  validation {
    condition     = !(local.cilium_installed && var.cloud == "azure") || try(var.cluster_network.pod_cidr != null, false)
    error_message = "cluster_network.pod_cidr is required on azure: Cilium's cluster pool must not default to 10.0.0.0/8, which contains the VNet."
  }

  validation {
    condition     = !local.cilium_installed || var.cluster_network == null || can(regex("^(https://)?[A-Za-z0-9.-]+(:[0-9]+)?/?$", var.cluster_network.api_endpoint))
    error_message = "cluster_network.api_endpoint must be a host name, with or without https:// and a port — what the foundations' cluster_endpoint output is."
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
