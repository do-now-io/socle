# One module for four clouds. Nothing here names a cloud provider; `cloud`
# picks the artifact's overlay and the operator's cluster type, and that is
# the only thing that differs between EKS, GKE, AKS and Kapsule.
#
# Every variable is typed, every constraint is a validation block with a test
# that trips it, and every default is the position docs/decisions/socle.md argues.

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
    condition     = can(regex("^[a-z0-9]([a-z0-9_-]{0,61}[a-z0-9])?$", var.owner))
    error_message = "owner must be a Kubernetes label value: 1 to 63 characters of lowercase letters, digits, dashes and underscores, starting and ending with a letter or a digit."
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

variable "project" {
  description = <<-EOT
    On gcp, the project the cluster runs in, as `{ id, number }` — the
    foundations' project_id and project_number outputs, never the client's.
    Exposed to the catalog as inputs.cluster.projectId and projectNumber: a
    module's Workload Identity principal names the project number, and the
    pool named after the project id. Required on gcp, refused elsewhere.
  EOT
  type = object({
    id     = string
    number = string
  })
  default = null

  validation {
    condition     = var.cloud != "gcp" || var.project != null
    error_message = "project is required on gcp: every module's Workload Identity principal names it. Pass the foundations' project_id and project_number (the gcp root wires them)."
  }

  validation {
    condition     = var.cloud == "gcp" || var.project == null
    error_message = "project is only configurable on gcp: the other clouds have no project, and their templates read none."
  }

  validation {
    condition     = var.project == null || can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", try(var.project.id, "")))
    error_message = "project.id must be a GCP project ID, such as sandbox-2bace: 6 to 30 lowercase letters, digits and dashes, starting with a letter."
  }

  validation {
    condition     = var.project == null || can(regex("^[1-9][0-9]{0,18}$", try(var.project.number, "")))
    error_message = "project.number must be the project's number, digits only, such as 123456789012 — not its ID: a Workload Identity principal names the number."
  }
}

# ---------------------------------------------------------------------------
# The catalog — docs/reference/inputs.md and docs/architecture/flux-catalog.md
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
    The schema is catalog.tf; docs/reference/inputs.md lists it module by module.
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

  # The same two checks one level down, for an attribute whose default is a
  # non-empty object (monitoring.logs, monitoring.alerting…): a misspelt key
  # inside it is an error at plan, and each key has its default's type. An
  # empty default ({}, as values or route) is free-form and not looked into.
  validation {
    condition = !can(keys(var.kube)) || alltrue(flatten([
      for m, v in var.kube : [
        for a in try(keys(v), []) : [
          for k in try(keys(v[a]), []) : contains(keys(lookup(local.catalog, m, {})[a]), k)
        ] if contains(keys(lookup(local.catalog, m, {})), a) && length(try(keys(lookup(local.catalog, m, {})[a]), [])) > 0
      ]
    ]))
    error_message = "kube: unknown attribute in a nested block. Allowed: ${jsonencode({ for m, d in local.catalog : m => { for a, x in d : a => keys(x) if length(try(keys(x), [])) > 0 } if anytrue([for a, x in d : length(try(keys(x), [])) > 0]) })}."
  }

  validation {
    condition = !can(keys(var.kube)) || alltrue(flatten([
      for m, v in var.kube : [
        for a in try(keys(v), []) : [
          for k in try(keys(v[a]), []) :
          !contains(keys(lookup(local.catalog, m, {})[a]), k)
          || lookup(local.json_kinds, substr(jsonencode(v[a][k]), 0, 1), "number") == lookup(local.json_kinds, substr(jsonencode(lookup(local.catalog, m, {})[a][k]), 0, 1), "number")
        ] if contains(keys(lookup(local.catalog, m, {})), a) && length(try(keys(lookup(local.catalog, m, {})[a]), [])) > 0
      ]
    ]))
    error_message = "kube: an attribute in a nested block has the wrong type. Each value must have the type of its catalog default: ${jsonencode({ for m, d in local.catalog : m => { for a, x in d : a => { for k, y in x : k => lookup(local.json_kinds, substr(jsonencode(y), 0, 1), "number") } if length(try(keys(x), [])) > 0 } if anytrue([for a, x in d : length(try(keys(x), [])) > 0]) })}."
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
    error_message = "kube.crossplane.permissions_boundary must be empty or an IAM policy ARN, such as arn:aws:iam::123456789012:policy/socle/acme-prod/acme-prod-crossplane-boundary."
  }

  # On gcp nothing carries a boundary: what Crossplane may grant is bounded
  # by the condition on its own binding, the foundations' allowed_roles. A
  # boundary written there would be silently ignored.
  validation {
    condition     = !can(keys(var.kube)) || var.cloud != "gcp" || try(var.kube.crossplane.permissions_boundary == "", true)
    error_message = "kube.crossplane.permissions_boundary is aws's: on gcp no binding carries a boundary, the foundations' crossplane.allowed_roles bound what Crossplane may grant. Leave it empty."
  }

  # The custom role external-dns writes DNS records with is gcp's: the gcp
  # root wires it from the foundations. Elsewhere nothing reads it, so a
  # value there is a mistake.
  validation {
    condition     = !can(keys(var.kube)) || var.cloud == "gcp" || try(var.kube.crossplane.dns_records_role == "", true)
    error_message = "kube.crossplane.dns_records_role is gcp's: the custom role Crossplane grants external-dns on the project, wired by the gcp root from the foundations. Leave it empty on ${var.cloud}."
  }

  # The root wires it from the foundations' dns_records_role output; a client
  # who writes it himself must write a project-level custom role.
  validation {
    condition     = !can(var.kube.crossplane.dns_records_role) || try(var.kube.crossplane.dns_records_role == "" || can(regex("^projects/[a-z][a-z0-9-]{4,28}[a-z0-9]/roles/[A-Za-z0-9_.]{3,64}$", var.kube.crossplane.dns_records_role)), true)
    error_message = "kube.crossplane.dns_records_role must be empty or a project custom role's full name, such as projects/sandbox-2bace/roles/socleDnsRecords_acme_prod."
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

  # On AWS with Crossplane on, the module declares its own role and a Pod
  # Identity association, which names the cluster's region: the socle's
  # ClusterProviderConfig carries none, so an empty region would reach AWS
  # as an invalid association rather than fail here.
  validation {
    condition     = !can(keys(var.kube)) || var.cloud != "aws" || !try(var.kube.external_dns.enabled, false) || !try(var.kube.crossplane.enabled, false) || var.region != ""
    error_message = "kube.external_dns with kube.crossplane on AWS needs the cluster's region: the module's Pod Identity association is regional. Pass region to the bootstrap module (the aws root wires var.aws.region)."
  }

  # On gcp with Crossplane on, the module's access is a binding of the
  # foundations' DNS records role, which Crossplane declares. Without the
  # role there is nothing to bind: external-dns would run with no access to
  # Cloud DNS and every write would fail at IAM, on the pod's logs only.
  validation {
    condition     = !can(keys(var.kube)) || var.cloud != "gcp" || !try(var.kube.external_dns.enabled, false) || !try(var.kube.crossplane.enabled, false) || try(var.kube.crossplane.dns_records_role != "", false)
    error_message = "kube.external_dns with kube.crossplane on gcp needs kube.crossplane.dns_records_role: the project custom role Crossplane binds external-dns to, to write DNS records. The gcp root wires it from the foundations' dns_records_role once gcp.crossplane is set; otherwise name it yourself (projects/<id>/roles/<role>), or turn kube.crossplane off and grant external-dns's principal its access yourself."
  }

  # values is free-form on purpose, minus one rule: no secret material. What a
  # client writes there ends up in the OpenTofu state and in a ConfigMap on the
  # cluster. external-dns takes its provider credentials from the environment
  # and a few flags, so those are the chart paths refused: secretConfiguration
  # (the chart's deprecated Secret-from-values), an env entry of the pod or of
  # the webhook sidecar whose name looks like a credential and carries a
  # literal value (valueFrom is fine), and an extraArgs flag that looks like
  # one (txt-encrypt-aes-key, pdns-api-key, rfc2136-tsig-secret…).
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

  validation {
    condition     = !can(var.kube.argocd.gateway) || try(contains(["private", "public", ""], var.kube.argocd.gateway), true)
    error_message = "kube.argocd.gateway must be private, public, or empty for no HTTPRoute: the shared Gateway ArgoCD's route attaches to."
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

  # --- argocd_image_updater — docs/catalog/argocd-image-updater.md ----------
  # It moves ArgoCD's Applications: without argocd there is nothing to move,
  # and its ResourceSet would wait on argocd's for nothing.
  validation {
    condition     = !can(keys(var.kube)) || !try(var.kube.argocd_image_updater.enabled, false) || try(var.kube.argocd.enabled, true)
    error_message = "kube.argocd_image_updater needs ArgoCD: set kube.argocd.enabled = true, or turn both off in the same change."
  }

  # On aws, repository names as ECR writes them, with * for a glob, each
  # naming something: a bare * would be every repository of the registry.
  # On gcp, an Artifact Registry repository of the cluster's project as
  # LOCATION/REPOSITORY: the location names the registry host
  # (<location>-docker.pkg.dev), and the reader role is granted on the
  # project, so a glob would add nothing.
  validation {
    condition = !can(keys(var.kube)) || alltrue([
      for r in try(tolist(var.kube.argocd_image_updater.repositories), []) :
      var.cloud == "gcp"
      ? can(regex("^[a-z][a-z0-9-]*[a-z0-9]/[a-z]([a-z0-9-]{0,61}[a-z0-9])?$", r))
      : (can(regex("^[a-z0-9*][a-z0-9._/*-]{0,255}$", r)) && can(regex("[a-z0-9]", r)))
    ])
    error_message = "kube.argocd_image_updater.repositories: on aws each entry must be an ECR repository name, such as crm-api or acme/front — lowercase letters, digits, '.', '_', '-' and '/' — with * for a glob such as acme/*, never * alone; on gcp, LOCATION/REPOSITORY of the cluster's project, such as europe-west1/apps; no glob."
  }

  # The role reading those repositories is a Crossplane managed resource.
  validation {
    condition     = !can(keys(var.kube)) || length(try(tolist(var.kube.argocd_image_updater.repositories), [])) == 0 || try(var.kube.crossplane.enabled, false)
    error_message = "kube.argocd_image_updater.repositories names ECR repositories, so Image Updater needs its own role, which only Crossplane creates: set kube.crossplane.enabled = true (and ecr in the foundations' aws.crossplane.allowed_services; on gcp, roles/artifactregistry.reader in the foundations' crossplane.allowed_roles), or leave repositories empty and configure the registry through registries with a credential of yours."
  }

  validation {
    condition     = !can(keys(var.kube)) || length(try(tolist(var.kube.argocd_image_updater.repositories), [])) == 0 || contains(["aws", "gcp"], var.cloud)
    error_message = "kube.argocd_image_updater.repositories names the cloud's own repositories — ECR repositories on aws, Artifact Registry repositories on gcp — and ${var.cloud} has none the socle reads. Configure your registry through registries, with a credential in a Secret of yours, and leave repositories empty."
  }

  # On gcp the socle writes one registry entry per location named in
  # repositories; Image Updater keys entries by prefix, so one of the
  # client's for the same host would silently replace it, or never be read.
  # The aws twin of this rule is a precondition in main.tf: there the host
  # carries the account, which a rule on var.kube cannot know.
  validation {
    condition = !can(keys(var.kube)) || var.cloud != "gcp" || !anytrue([
      for r in try(tolist(var.kube.argocd_image_updater.registries), []) :
      anytrue([for x in try(tolist(var.kube.argocd_image_updater.repositories), []) :
      startswith(lower(try(r.prefix, "")), "${split("/", x)[0]}-docker.pkg.dev")])
    ])
    error_message = "kube.argocd_image_updater.registries names <location>-docker.pkg.dev, which the socle already configures from repositories. To read one more repository of that location, add it to kube.argocd_image_updater.repositories."
  }

  validation {
    condition     = !can(keys(var.kube)) || var.cloud != "aws" || length(try(tolist(var.kube.argocd_image_updater.repositories), [])) == 0 || var.region != ""
    error_message = "kube.argocd_image_updater.repositories needs the cluster's region: the repositories' ARNs, the registry's address and the Pod Identity association are regional. Pass region to the bootstrap module (the aws root wires var.aws.region)."
  }

  # Each entry is a registry as Image Updater's registries.conf writes it.
  # credentials is a reference — to a Secret, a pull secret, an environment
  # variable or a script — never the credential itself.
  validation {
    condition = !can(keys(var.kube)) || alltrue([
      for r in try(tolist(var.kube.argocd_image_updater.registries), []) :
      can(keys(r))
      && alltrue([for k in try(keys(r), []) : contains(["name", "prefix", "api_url", "credentials", "credsexpire", "insecure", "ping", "defaultns", "default", "tagsortmode", "limit", "ca_file", "ca_data"], k)])
      && can(regex("^[A-Za-z0-9][A-Za-z0-9 ._-]*$", r.name))
      && can(regex("^[^\\s/][^\\s]*$", r.prefix))
      && can(regex("^https?://[^\\s]+$", r.api_url))
      && try(r.credentials == "" || can(regex("^(secret|pullsecret|env|ext):[^\\s]+$", r.credentials)), true)
    ])
    error_message = "kube.argocd_image_updater.registries: each entry must be an object with name, prefix (the registry host, such as ghcr.io) and api_url (https://…), and only registries.conf keys (credentials, credsexpire, insecure, ping, defaultns, default, tagsortmode, limit, ca_file, ca_data). credentials must be a reference — secret:<namespace>/<secret>#<key>, pullsecret:<namespace>/<secret>, env:<VARIABLE> or ext:<script> — never the credential itself."
  }

  # values is free-form on purpose, minus two rules. A registry entry goes
  # through registries: the chart's config.registries is a list, which
  # helm-controller replaces whole, so one from values would drop the socle's
  # ECR entry. And no secret material, which would reach the state and a
  # ConfigMap: a Secret among extraObjects, an extraEnv entry with a literal
  # value named like a credential, and authScripts, whose scripts are where
  # a registry token is written by hand.
  validation {
    condition = (
      !can(var.kube.argocd_image_updater.values)
      || !can(keys(var.kube.argocd_image_updater.values))
      || (
        !can(var.kube.argocd_image_updater.values.config.registries)
        && !can(var.kube.argocd_image_updater.values.authScripts)
        && !anytrue(try([for o in var.kube.argocd_image_updater.values.extraObjects : try(o.kind == "Secret", false)], []))
        && alltrue([
          for e in try(tolist(var.kube.argocd_image_updater.values.extraEnv), []) :
          !(can(e.value) && can(regex("(?i)(secret|password|passwd|token|credential|api_?key|access_?key|private_?key)", try(e.name, ""))))
        ])
      )
    )
    error_message = "kube.argocd_image_updater.values: config.registries is refused — list your registries in kube.argocd_image_updater.registries, after the socle's ECR entry. Secrets are refused too: authScripts, a Secret in extraObjects, and an extraEnv entry with a literal value named like a credential. Put them in a Secret in argocd-image-updater and name it in kube.argocd_image_updater.values_secret, or reference it from a registry's credentials."
  }

  validation {
    condition     = !can(var.kube.argocd_image_updater.values_secret) || try(var.kube.argocd_image_updater.values_secret == "" || can(regex("^[a-z0-9]([-a-z0-9.]{0,251}[a-z0-9])?$", var.kube.argocd_image_updater.values_secret)), true)
    error_message = "kube.argocd_image_updater.values_secret must be empty or a valid Kubernetes Secret name (lowercase RFC 1123 subdomain)."
  }

  # --- otel_agent — docs/catalog/otel-agent.md -----------------------------
  # values is free-form on purpose, minus one rule: no secret material. The
  # collector takes credentials in its own config — an authenticator
  # extension's token or password, an exporter's Authorization header — and
  # from the environment. A value written as an environment reference,
  # ${env:NAME}, is the collector's own way to read a Secret and is accepted;
  # a literal is refused, as are an extraEnvs entry with a literal value named
  # like a credential (valueFrom is fine) and a Secret among extraManifests.
  validation {
    condition = (
      !can(var.kube.otel_agent.values)
      || !can(keys(var.kube.otel_agent.values))
      || (
        !anytrue(flatten([
          for n, e in try(var.kube.otel_agent.values.config.extensions, {}) : [
            for v in [try(e.token, null), try(e.client_auth.password, null), try(e.htpasswd.inline, null), try(e.client_secret, null)] :
            v != null && !can(regex("^\\$\\{env:[A-Za-z_][A-Za-z0-9_]*\\}$", v))
          ]
        ]))
        && !anytrue(flatten([
          for n, x in try(var.kube.otel_agent.values.config.exporters, {}) : [
            for h, v in try(x.headers, {}) :
            can(regex("(?i)^(authorization|proxy-authorization|x-api-key|api-key|x-auth-token)$", h)) && !can(regex("^[A-Za-z]* ?\\$\\{env:[A-Za-z_][A-Za-z0-9_]*\\}$", v))
          ]
        ]))
        && alltrue([
          for e in try(tolist(var.kube.otel_agent.values.extraEnvs), []) :
          !(can(e.value) && can(regex("(?i)(secret|password|passwd|token|api_?key|access_?key|private_?key)", try(e.name, ""))))
        ])
        && !anytrue(try([for o in var.kube.otel_agent.values.extraManifests : try(o.kind == "Secret", false)], []))
      )
    )
    error_message = "kube.otel_agent.values must not carry secrets: a literal token, password or client secret in a config.extensions authenticator, a literal Authorization or API-key header in a config.exporters entry, an extraEnvs entry with a literal value named like a credential, and a Secret in extraManifests are refused. Read them from the environment instead — $${env:NAME}, the variable set by extraEnvs valueFrom a Secret — or put them in a Secret in the otel-agent namespace named in kube.otel_agent.values_secret."
  }

  validation {
    condition     = !can(var.kube.otel_agent.values_secret) || try(var.kube.otel_agent.values_secret == "" || can(regex("^[a-z0-9]([-a-z0-9.]{0,251}[a-z0-9])?$", var.kube.otel_agent.values_secret)), true)
    error_message = "kube.otel_agent.values_secret must be empty or a valid Kubernetes Secret name (lowercase RFC 1123 subdomain)."
  }

  # --- otel_gateway — docs/catalog/otel-gateway.md -------------------------
  # The same rule as otel_agent, on the same chart: the paths a credential
  # takes are the collector's, whichever mode it runs in.
  # values is free-form on purpose, minus one rule: no secret material. The
  # collector takes credentials in its own config — an authenticator
  # extension's token or password, an exporter's Authorization header — and
  # from the environment. A value written as an environment reference,
  # ${env:NAME}, is the collector's own way to read a Secret and is accepted;
  # a literal is refused, as are an extraEnvs entry with a literal value named
  # like a credential (valueFrom is fine) and a Secret among extraManifests.
  validation {
    condition = (
      !can(var.kube.otel_gateway.values)
      || !can(keys(var.kube.otel_gateway.values))
      || (
        !anytrue(flatten([
          for n, e in try(var.kube.otel_gateway.values.config.extensions, {}) : [
            for v in [try(e.token, null), try(e.client_auth.password, null), try(e.htpasswd.inline, null), try(e.client_secret, null)] :
            v != null && !can(regex("^\\$\\{env:[A-Za-z_][A-Za-z0-9_]*\\}$", v))
          ]
        ]))
        && !anytrue(flatten([
          for n, x in try(var.kube.otel_gateway.values.config.exporters, {}) : [
            for h, v in try(x.headers, {}) :
            can(regex("(?i)^(authorization|proxy-authorization|x-api-key|api-key|x-auth-token)$", h)) && !can(regex("^[A-Za-z]* ?\\$\\{env:[A-Za-z_][A-Za-z0-9_]*\\}$", v))
          ]
        ]))
        && alltrue([
          for e in try(tolist(var.kube.otel_gateway.values.extraEnvs), []) :
          !(can(e.value) && can(regex("(?i)(secret|password|passwd|token|api_?key|access_?key|private_?key)", try(e.name, ""))))
        ])
        && !anytrue(try([for o in var.kube.otel_gateway.values.extraManifests : try(o.kind == "Secret", false)], []))
      )
    )
    error_message = "kube.otel_gateway.values must not carry secrets: a literal token, password or client secret in a config.extensions authenticator, a literal Authorization or API-key header in a config.exporters entry, an extraEnvs entry with a literal value named like a credential, and a Secret in extraManifests are refused. Read them from the environment instead — $${env:NAME}, the variable set by extraEnvs valueFrom a Secret — or put them in a Secret in the otel-gateway namespace named in kube.otel_gateway.values_secret."
  }

  validation {
    condition     = !can(var.kube.otel_gateway.values_secret) || try(var.kube.otel_gateway.values_secret == "" || can(regex("^[a-z0-9]([-a-z0-9.]{0,251}[a-z0-9])?$", var.kube.otel_gateway.values_secret)), true)
    error_message = "kube.otel_gateway.values_secret must be empty or a valid Kubernetes Secret name (lowercase RFC 1123 subdomain)."
  }

  # --- monitoring — docs/catalog/monitoring.md ------------------------------
  # Each rule reads var.kube with the catalog default as the fallback, as the
  # rest of this block does. A value of the wrong kind is the kind checks' to
  # refuse; these rules only judge strings, so one mistake gives one
  # diagnostic. Never tolist() on receivers or routes: two receivers of
  # different kinds (Slack, PagerDuty) are a tuple tolist() cannot convert,
  # and under try() that failure would read as an empty list and let
  # everything through.

  # What -retentionPeriod accepts, for each of the three backends, minus the
  # forms a client should not need (bare months, fractions, ms), and never
  # under their own one-day minimum.
  validation {
    condition = alltrue([
      for p in ["metrics", "logs", "traces"] : !can(var.kube.monitoring[p].retention) || try(
        lookup(local.json_kinds, substr(jsonencode(var.kube.monitoring[p].retention), 0, 1), "number") != "string"
        || can(regex("^[1-9][0-9]*[dwy]$", var.kube.monitoring[p].retention))
        || (can(regex("^[1-9][0-9]*h$", var.kube.monitoring[p].retention)) && tonumber(trimsuffix(var.kube.monitoring[p].retention, "h")) >= 24),
        false
      )
    ])
    error_message = "kube.monitoring: metrics, logs and traces retention must be a whole number of hours, days, weeks or years, such as 15d, 4w or 1y, and at least one day (24h): VictoriaMetrics, VictoriaLogs and VictoriaTraces refuse less."
  }

  validation {
    condition = alltrue([
      for p in ["metrics", "logs", "traces"] : !can(var.kube.monitoring[p].storage_size) || try(
        lookup(local.json_kinds, substr(jsonencode(var.kube.monitoring[p].storage_size), 0, 1), "number") != "string"
        || var.kube.monitoring[p].storage_size == ""
        || can(regex("^[1-9][0-9]*(Gi|Ti)$", var.kube.monitoring[p].storage_size)),
        false
      )
    ])
    error_message = "kube.monitoring: metrics, logs and traces storage_size must be empty (no volume claim, an emptyDir) or a size in Gi or Ti, such as 20Gi."
  }

  validation {
    condition = (
      !can(var.kube.monitoring.grafana.domain)
      || lookup(local.json_kinds, substr(jsonencode(var.kube.monitoring.grafana.domain), 0, 1), "number") != "string"
      || var.kube.monitoring.grafana.domain == ""
      || can(regex("^([a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", var.kube.monitoring.grafana.domain))
    )
    error_message = "kube.monitoring.grafana.domain must be empty or a fully qualified DNS name in lowercase, such as grafana.acme.example: no scheme, no port, no path."
  }

  validation {
    condition     = !can(var.kube.monitoring.grafana.gateway) || try(contains(["private", "public", ""], var.kube.monitoring.grafana.gateway), true)
    error_message = "kube.monitoring.grafana.gateway must be private, public, or empty for no HTTPRoute: the shared Gateway Grafana's route attaches to."
  }

  # Alerting on, alerts must go somewhere: a receiver of the client's, named
  # by the default route. watchdog and null are the socle's; neither may be
  # the client's.
  validation {
    condition = !try(var.kube.monitoring.alerting.enabled == true, false) || try(
      length(var.kube.monitoring.alerting.receivers) > 0
      && alltrue([for r in var.kube.monitoring.alerting.receivers : can(regex("^[A-Za-z0-9_.-]+$", r.name))])
      && contains([for r in var.kube.monitoring.alerting.receivers : r.name], var.kube.monitoring.alerting.route.receiver),
      false
    )
    error_message = "kube.monitoring.alerting on needs where alerts go: at least one receiver in receivers, each with a name, and route.receiver naming one of them (Alertmanager's routing tree, docs/catalog/monitoring.md)."
  }

  validation {
    condition     = alltrue([for r in try(var.kube.monitoring.alerting.receivers, []) : !contains(["watchdog", "null"], try(r.name, ""))])
    error_message = "kube.monitoring.alerting.receivers: watchdog and null are the socle's receivers — the dead man's switch, and the one that drops info alerts; name yours otherwise."
  }

  # A sub-route naming a receiver that does not exist stops Alertmanager from
  # loading its configuration at all. Checked two levels down, where routing
  # trees live in practice. null, the socle's, is there to route to.
  validation {
    condition = alltrue(flatten([
      for r in concat(
        try(var.kube.monitoring.alerting.route.routes, []),
        flatten([for c in try(var.kube.monitoring.alerting.route.routes, []) : try(c.routes, [])])
      ) : !can(r.receiver) || contains(concat(["watchdog", "null"], [for x in try(var.kube.monitoring.alerting.receivers, []) : try(x.name, "")]), try(r.receiver, ""))
    ]))
    error_message = "kube.monitoring.alerting.route: a sub-route names a receiver that is not in receivers. Alertmanager refuses its whole configuration over it."
  }

  # The watchdog's URL is a key: it lives in receivers_secret, never in the
  # plan. On with the watchdog, that Secret must be named — or the watchdog
  # turned off in the open.
  validation {
    condition     = !try(var.kube.monitoring.alerting.enabled == true, false) || try(var.kube.monitoring.alerting.watchdog == false, false) || try(var.kube.monitoring.alerting.receivers_secret, "") != ""
    error_message = "kube.monitoring.alerting on with the watchdog needs receivers_secret: a Secret you create in the monitoring namespace, whose watchdog-url key is your dead man's switch (Healthchecks.io, your on-call platform's heartbeat). Or set watchdog = false, knowing nothing will tell you when alerting itself is down."
  }

  # Everything in the plan lands in the OpenTofu state and in a ConfigMap on
  # the cluster. A receiver's key — a Slack webhook URL, a PagerDuty routing
  # key, a password — goes in receivers_secret and is read through its
  # *_file twin, which Alertmanager has for every one of them.
  validation {
    condition = alltrue(flatten([
      for r in try(var.kube.monitoring.alerting.receivers, []) : [
        for k in try(keys(r), []) : [
          for c in try(r[k], []) : (
            length(setintersection(try(keys(c), []), local.alerting_literal_keys)) == 0
            && !can(c.http_config.basic_auth.password)
            && !can(c.http_config.authorization.credentials)
            && !can(c.http_config.oauth2.client_secret)
            && !can(c.http_config.bearer_token)
            && !can(c.sigv4.secret_key)
          )
        ] if endswith(k, "_configs")
      ]
    ]))
    error_message = "kube.monitoring.alerting.receivers must not carry keys in clear: ${join(", ", local.alerting_literal_keys)}, and an http_config password, credentials, client_secret or bearer_token, are refused. Put the key in receivers_secret and use the *_file twin: api_url_file, routing_key_file, url_file… pointing under /etc/alertmanager/secrets/."
  }

  validation {
    condition     = !can(var.kube.monitoring.alerting.receivers_secret) || try(var.kube.monitoring.alerting.receivers_secret == "" || can(regex("^[a-z0-9]([-a-z0-9.]{0,251}[a-z0-9])?$", var.kube.monitoring.alerting.receivers_secret)), true)
    error_message = "kube.monitoring.alerting.receivers_secret must be empty or a valid Kubernetes Secret name (lowercase RFC 1123 subdomain)."
  }

  # values tunes the chart, minus what the socle builds from named
  # attributes: Alertmanager's configuration, rendered from receivers, route
  # and the watchdog, which a configuration in values would silently
  # replace; the rules' sources, pinned to the tags the socle tests; and the
  # parts the attributes switch, which values would switch behind them.
  validation {
    condition = !can(keys(var.kube.monitoring.values)) || (
      !can(var.kube.monitoring.values.alertmanager.config)
      && try(var.kube.monitoring.values.alertmanager.spec.configSecret, "") == ""
      && try(var.kube.monitoring.values.alertmanager.spec.configRawYaml, "") == ""
      && !try(var.kube.monitoring.values.alertmanager.useManagedConfig, false)
      && !can(var.kube.monitoring.values.defaultRules.sources)
      && alltrue([for c in ["vmsingle", "vlsingle", "vtsingle", "vmalert", "alertmanager", "grafana", "defaultRules", "defaultDashboards"] : !can(var.kube.monitoring.values[c].enabled)])
    )
    error_message = "kube.monitoring.values must not set Alertmanager's configuration (alertmanager.config, alertmanager.spec.configSecret or configRawYaml, alertmanager.useManagedConfig), the rules' sources (defaultRules.sources), or the enabled switch of vmsingle, vlsingle, vtsingle, vmalert, alertmanager, grafana, defaultRules and defaultDashboards. Where alerts go is alerting.receivers and route; what runs is the module's attributes."
  }

  # And no secret material in values. VictoriaMetrics, VictoriaLogs,
  # VictoriaTraces, vmagent and vmalert take credentials as flags and as
  # environment variables; Grafana in its own paths. Refused: an extraArgs
  # flag named like a password or an auth key (httpAuth.password,
  # deleteAuthKey…), an extraEnvs or env entry with a literal value named like
  # a credential (valueFrom is fine), Grafana's adminPassword, grafana.ini's
  # security, database and smtp passwords, an auth.* client_secret, and a
  # Secret among extraObjects.
  validation {
    condition = !can(keys(var.kube.monitoring.values)) || (
      !anytrue(try([for o in var.kube.monitoring.values.extraObjects : try(o.kind == "Secret", false)], []))
      && !anytrue(flatten([
        for c in ["vmsingle", "vlsingle", "vtsingle", "vmagent", "vmalert", "alertmanager"] : concat(
          [for k in try(keys(var.kube.monitoring.values[c].spec.extraArgs), []) : can(regex("(?i)(password|passwd|auth_?key|token)", k))],
          [for e in try(tolist(var.kube.monitoring.values[c].spec.extraEnvs), []) : can(e.value) && can(regex("(?i)(secret|password|passwd|token|auth_?key|api_?key|access_?key|private_?key)", try(e.name, "")))],
        )
      ]))
      && !can(var.kube.monitoring.values.grafana.adminPassword)
      && !can(var.kube.monitoring.values.grafana["grafana.ini"].security.admin_password)
      && !can(var.kube.monitoring.values.grafana["grafana.ini"].security.secret_key)
      && !can(var.kube.monitoring.values.grafana["grafana.ini"].database.password)
      && !can(var.kube.monitoring.values.grafana["grafana.ini"].smtp.password)
      && !anytrue([for s, v in try(var.kube.monitoring.values.grafana["grafana.ini"], {}) : startswith(s, "auth.") && can(v.client_secret)])
      && !anytrue([for k, v in try(var.kube.monitoring.values.grafana.env, {}) : can(regex("(?i)(password|passwd|secret|token|api_?key|private_?key)", k))])
      && !anytrue([for d in try(var.kube.monitoring.values.defaultDatasources.extra, []) : can(d.password) || can(d.basicAuthPassword)])
    )
    error_message = "kube.monitoring.values must not carry secrets: an extraArgs flag such as httpAuth.password or deleteAuthKey, an extraEnvs entry with a literal value named like a credential, grafana.adminPassword, grafana.ini security.admin_password and security.secret_key, database.password and smtp.password, an auth.* client_secret, a grafana.env entry named like a credential, a password in defaultDatasources.extra, and a Secret in extraObjects are refused. Name a Secret instead — grafana.admin.existingSecret, envValueFrom, an extraEnvs valueFrom — or put them in a Secret in the monitoring namespace named in kube.monitoring.values_secret."
  }

  validation {
    condition     = !can(var.kube.monitoring.values_secret) || try(var.kube.monitoring.values_secret == "" || can(regex("^[a-z0-9]([-a-z0-9.]{0,251}[a-z0-9])?$", var.kube.monitoring.values_secret)), true)
    error_message = "kube.monitoring.values_secret must be empty or a valid Kubernetes Secret name (lowercase RFC 1123 subdomain)."
  }

  # --- keda — docs/catalog/keda.md -------------------------------------------
  # services is the list of the cloud's services KEDA's own role may read.
  # Each entry is one the module knows how to scope to the scaler's exact
  # read calls on this cloud; anything else is refused, with the list — a
  # service the module cannot scope would otherwise get nothing, silently.
  # RDS has no scaler: its metrics are read through cloudwatch. A cloud with
  # no list is the next rule's to refuse.
  validation {
    condition     = !can(keys(var.kube)) || !contains(keys(local.keda_services), var.cloud) || alltrue([for x in try(tolist(var.kube.keda.services), []) : contains(lookup(local.keda_services, var.cloud, []), x)])
    error_message = var.cloud == "gcp" ? "kube.keda.services: unknown service on gcp. KEDA's own identity can read ${join(", ", local.keda_services.gcp)} — the GCP scalers the module scopes. A cron, Prometheus, Kafka, RabbitMQ or Redis trigger needs no entry." : "kube.keda.services: unknown service. KEDA's own role can read ${join(", ", local.keda_services.aws)} — the AWS scalers the module scopes. RDS metrics go through cloudwatch; a cron, Prometheus, Kafka, RabbitMQ or Redis trigger needs no entry."
  }

  # A named service is a role, and only Crossplane creates one: without it the
  # list would render nothing and the client's ScaledObjects would fail at the
  # AWS API. With Crossplane off, leave the list empty and bind keda/keda-operator
  # to an identity made outside the socle.
  validation {
    condition     = !can(keys(var.kube)) || length(try(tolist(var.kube.keda.services), [])) == 0 || try(var.kube.crossplane.enabled, false)
    error_message = var.cloud == "gcp" ? "kube.keda.services names a service, so KEDA needs its own cloud binding, which only Crossplane creates: set kube.crossplane.enabled = true (and roles/monitoring.viewer in the foundations' crossplane.allowed_roles), or leave services empty and bind keda/keda-operator to an identity you made yourself." : "kube.keda.services names a service, so KEDA needs its own cloud role, which only Crossplane creates: set kube.crossplane.enabled = true (and aws.crossplane.allowed_services in the foundations, naming the same services), or leave services empty and bind keda/keda-operator to an identity you made yourself."
  }

  # The role is declared on the clouds where the crossplane module has a
  # provider: aws and gcp. Elsewhere the client annotates keda-operator
  # through values (AKS workload identity).
  validation {
    condition     = !can(keys(var.kube)) || length(try(tolist(var.kube.keda.services), [])) == 0 || contains(keys(local.keda_services), var.cloud)
    error_message = "kube.keda.services is offered on ${join(" and ", keys(local.keda_services))} only for now: no other cloud has a Crossplane provider in the socle yet. Every scaler still works: reference a Secret from a TriggerAuthentication, or bind an identity you made to keda-operator through values (podIdentity.azureWorkload). Leave services empty."
  }

  # The Pod Identity association is regional; the socle's ClusterProviderConfig
  # carries no region, so an empty one would reach AWS as an invalid
  # association rather than fail here.
  validation {
    condition     = !can(keys(var.kube)) || var.cloud != "aws" || length(try(tolist(var.kube.keda.services), [])) == 0 || var.region != ""
    error_message = "kube.keda.services with kube.crossplane on AWS needs the cluster's region: the module's Pod Identity association is regional. Pass region to the bootstrap module (the aws root wires var.aws.region)."
  }

  # values is free-form on purpose, minus one rule: no secret material. What a
  # client writes there ends up in the OpenTofu state and in a ConfigMap on
  # the cluster. The keda chart takes no credential of its own; the places
  # one could still be smuggled in are refused: a Secret among extraObjects,
  # and an env entry of any of the three pods whose name says it carries one
  # and whose value is a literal (valueFrom is fine). Those go through
  # values_secret instead — or, better, through a TriggerAuthentication.
  validation {
    condition = (
      !can(var.kube.keda.values)
      || !can(keys(var.kube.keda.values))
      || (
        !anytrue(try([for o in var.kube.keda.values.extraObjects : try(o.kind == "Secret", false)], []))
        && alltrue([
          for e in concat(
            try(tolist(var.kube.keda.values.env), []),
            try(tolist(var.kube.keda.values.operator.env), []),
            try(tolist(var.kube.keda.values.metricsServer.env), []),
            try(tolist(var.kube.keda.values.webhooks.env), []),
          ) :
          !(can(e.value) && can(regex("(?i)(secret|password|passwd|token|api_?key|access_?key|private_?key|credential)", try(e.name, ""))))
        ])
      )
    )
    error_message = "kube.keda.values must not carry secrets: a Secret in extraObjects, and an env entry (env, operator.env, metricsServer.env, webhooks.env) with a literal value whose name looks like a credential (AWS_SECRET_ACCESS_KEY, *_TOKEN, …), are refused. Put them in a Secret in the keda namespace and name it in kube.keda.values_secret — or reference it from a TriggerAuthentication, which is what KEDA is for."
  }

  validation {
    condition     = !can(var.kube.keda.values_secret) || try(var.kube.keda.values_secret == "" || can(regex("^[a-z0-9]([-a-z0-9.]{0,251}[a-z0-9])?$", var.kube.keda.values_secret)), true)
    error_message = "kube.keda.values_secret must be empty or a valid Kubernetes Secret name (lowercase RFC 1123 subdomain)."
  }

  # --- kyverno — docs/catalog/kyverno.md -------------------------------------
  # values is free-form on purpose, minus one rule: no secret material. The
  # kyverno chart takes registry credentials for image verification inline,
  # in imagePullSecrets (registry, username, password): refused — the client
  # creates that Secret himself and names it in existingImagePullSecrets, or
  # puts the whole block in values_secret. And an extraEnvVars entry, on any
  # of the four controllers or the admission init container, whose name looks
  # like a credential and carries a literal value (valueFrom is fine).
  validation {
    condition = (
      !can(var.kube.kyverno.values)
      || !can(keys(var.kube.kyverno.values))
      || (
        length(try(keys(var.kube.kyverno.values.imagePullSecrets), [])) == 0
        && alltrue([
          for e in concat(
            try(tolist(var.kube.kyverno.values.admissionController.container.extraEnvVars), []),
            try(tolist(var.kube.kyverno.values.admissionController.initContainer.extraEnvVars), []),
            try(tolist(var.kube.kyverno.values.backgroundController.extraEnvVars), []),
            try(tolist(var.kube.kyverno.values.cleanupController.extraEnvVars), []),
            try(tolist(var.kube.kyverno.values.reportsController.extraEnvVars), []),
          ) :
          !(can(e.value) && can(regex("(?i)(secret|password|passwd|token|api_?key|access_?key|private_?key|credential)", try(e.name, ""))))
        ])
      )
    )
    error_message = "kube.kyverno.values must not carry secrets: imagePullSecrets with credentials, and an extraEnvVars entry with a literal value named like a credential, are refused. Create the registry Secret yourself and name it in existingImagePullSecrets, or put the values in a Secret in the kyverno namespace named in kube.kyverno.values_secret."
  }

  validation {
    condition     = !can(var.kube.kyverno.values_secret) || try(var.kube.kyverno.values_secret == "" || can(regex("^[a-z0-9]([-a-z0-9.]{0,251}[a-z0-9])?$", var.kube.kyverno.values_secret)), true)
    error_message = "kube.kyverno.values_secret must be empty or a valid Kubernetes Secret name (lowercase RFC 1123 subdomain)."
  }

  # --- kyverno_policies — docs/catalog/kyverno-policies.md -------------------
  # The policies' kinds are the engine's CRDs: without kyverno, the release
  # waits on its dependency forever and the socle never converges.
  validation {
    condition     = !can(keys(var.kube)) || !try(var.kube.kyverno_policies.enabled, false) || try(var.kube.kyverno.enabled, false)
    error_message = "kube.kyverno_policies needs the engine: set kube.kyverno.enabled = true as well."
  }

  validation {
    condition     = !can(var.kube.kyverno_policies.profile) || try(contains(["baseline", "restricted"], var.kube.kyverno_policies.profile), true)
    error_message = "kube.kyverno_policies.profile must be baseline (the Pod Security Standards' baseline profile) or restricted (baseline plus the restricted policies)."
  }

  # enforce may only name a policy this configuration renders: a restricted
  # one with profile = restricted, the registry one with an allow-list. A
  # name nothing renders would be a switch that silently does nothing.
  validation {
    condition = !can(var.kube.kyverno_policies.enforce) || try(alltrue([
      for p in tolist(var.kube.kyverno_policies.enforce) : contains(concat(
        local.kyverno_policies.baseline,
        local.kyverno_policies.socle,
        try(var.kube.kyverno_policies.profile, "baseline") == "restricted" ? local.kyverno_policies.restricted : [],
        length(try(tolist(var.kube.kyverno_policies.allowed_registries), [])) > 0 ? local.kyverno_policies.registries : [],
      ), p)
    ]), true)
    error_message = "kube.kyverno_policies.enforce names a policy this configuration does not render. Baseline and socle: ${join(", ", concat(local.kyverno_policies.baseline, local.kyverno_policies.socle))}; with profile = restricted also ${join(", ", local.kyverno_policies.restricted)}; with allowed_registries also restrict-image-registries."
  }

  # A registry as an image reference starts with it: a host (a dot, a port
  # or localhost), optionally a path under it. No scheme, no trailing slash,
  # no tag — the policy matches the prefix plus a slash, so ghcr.io never
  # admits ghcr.io.evil.example.
  validation {
    condition = !can(var.kube.kyverno_policies.allowed_registries) || try(alltrue([
      for r in tolist(var.kube.kyverno_policies.allowed_registries) :
      can(regex("^(localhost|[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+)(:[0-9]{1,5})?(/[a-z0-9]+([._-][a-z0-9]+)*)*$", r))
    ]), true)
    error_message = "kube.kyverno_policies.allowed_registries entries must be registry hosts, optionally with a port and a path under them, such as ghcr.io, registry.k8s.io or ghcr.io/acme: lowercase, no scheme, no trailing slash. A Docker Hub image is docker.io/<path>."
  }

  # The kyverno-policies chart carries no credential, so values has no path
  # to refuse; only the Secret's name is checked.
  validation {
    condition     = !can(var.kube.kyverno_policies.values_secret) || try(var.kube.kyverno_policies.values_secret == "" || can(regex("^[a-z0-9]([-a-z0-9.]{0,251}[a-z0-9])?$", var.kube.kyverno_policies.values_secret)), true)
    error_message = "kube.kyverno_policies.values_secret must be empty or a valid Kubernetes Secret name (lowercase RFC 1123 subdomain)."
  }

  # --- reloader — docs/catalog/reloader.md -----------------------------------
  # Opt-in per workload, by decision: autoReloadAll rolls every Deployment,
  # StatefulSet and DaemonSet of the cluster on any change to anything it
  # reads, which is not a default a platform can choose for its tenants. A
  # client who wants it for one workload writes reloader.stakater.com/auto on
  # it. (values_secret is never read here, so a Secret could still set it:
  # that one is the client's own, reviewed outside the socle.)
  validation {
    condition     = !can(var.kube.reloader.values) || !can(keys(var.kube.reloader.values)) || try(var.kube.reloader.values.reloader.autoReloadAll, false) != true
    error_message = "kube.reloader.values.reloader.autoReloadAll is refused: Reloader in the socle is opt-in per workload. Annotate the workloads to roll with reloader.stakater.com/auto: \"true\" (or secret.reloader.stakater.com/reload / configmap.reloader.stakater.com/reload naming the objects)."
  }

  # values is free-form on purpose, minus one rule: no secret material. What a
  # client writes there ends up in the OpenTofu state and in a ConfigMap on
  # the cluster. Reloader's chart turns reloader.deployment.env.secret into a
  # Secret of its own — its alerting webhook URL is a credential — and
  # env.open into literal environment variables, so those are the paths
  # refused: any env.secret entry, and an env.open entry named like a
  # credential. They go through values_secret, or through env.existing, which
  # names a Secret the client made.
  validation {
    condition = (
      !can(var.kube.reloader.values)
      || !can(keys(var.kube.reloader.values))
      || (
        length(try(keys(var.kube.reloader.values.reloader.deployment.env.secret), [])) == 0
        && !anytrue([for k in try(keys(var.kube.reloader.values.reloader.deployment.env.open), []) : can(regex("(?i)(secret|password|passwd|token|webhook|api_?key|access_?key|private_?key|credential)", k))])
      )
    )
    error_message = "kube.reloader.values must not carry secrets: reloader.deployment.env.secret, and a reloader.deployment.env.open entry named like a credential (ALERT_WEBHOOK_URL, *_TOKEN, …), are refused. Create a Secret in the reloader namespace and reference it from reloader.deployment.env.existing, or put the values in a Secret named in kube.reloader.values_secret."
  }

  validation {
    condition     = !can(var.kube.reloader.values_secret) || try(var.kube.reloader.values_secret == "" || can(regex("^[a-z0-9]([-a-z0-9.]{0,251}[a-z0-9])?$", var.kube.reloader.values_secret)), true)
    error_message = "kube.reloader.values_secret must be empty or a valid Kubernetes Secret name (lowercase RFC 1123 subdomain)."
  }

  # --- external_secrets — docs/catalog/external-secrets.md -------------------
  # prefixes scope the module's own read-only role: GetSecretValue and
  # DescribeSecret on secret:<prefix>/* for each. A prefix is a Secrets
  # Manager name path — the characters a secret name allows, segments
  # separated by "/", none empty — and never a wildcard: "*" or a trailing
  # "/" would widen the role past what the client named.
  validation {
    condition = !can(var.kube.external_secrets.prefixes) || var.cloud == "gcp" || try(alltrue([
      for p in tolist(var.kube.external_secrets.prefixes) :
      can(regex("^[A-Za-z0-9_+=.@-]+(/[A-Za-z0-9_+=.@-]+)*$", p)) && length(p) <= 256
    ]), false)
    error_message = "kube.external_secrets.prefixes must be a list of Secrets Manager name paths such as \"acme-prod\" or \"shared/platform\": letters, digits and _+=.@-, segments separated by \"/\", no leading or trailing \"/\", no wildcard. The role reads secret:<prefix>/* for each."
  }

  # On gcp a Secret Manager secret ID has no path: the module binds the
  # accessor role on the secrets named <prefix>_<name>, "_" standing where
  # "/" does on aws. A prefix holding "_" would blur that separator — acme
  # would then read acme_prod_* too — and a "/" would match no secret, so
  # the binding would grant nothing, silently.
  validation {
    condition = !can(var.kube.external_secrets.prefixes) || var.cloud != "gcp" || try(alltrue([
      for p in tolist(var.kube.external_secrets.prefixes) : can(regex("^[A-Za-z0-9-]{1,255}$", p))
    ]), false)
    error_message = "kube.external_secrets.prefixes on gcp must be a list of Secret Manager name prefixes such as \"acme-prod\" or \"my-app\": letters, digits and -, no \"_\", no \"/\", no wildcard. Secrets are named <prefix>_<name>; the binding reads the secrets whose name starts with <prefix>_ for each."
  }

  # The Pod Identity association is regional and so is the role's ARN scope;
  # the socle's ClusterProviderConfig carries no region, so an empty one would
  # reach AWS as an invalid association and a policy that matches nothing.
  validation {
    condition = (
      !can(keys(var.kube)) || var.cloud != "aws" || var.region != ""
      || !try(var.kube.external_secrets.enabled, false)
      || !try(var.kube.crossplane.enabled, false)
      || length(try(tolist(var.kube.external_secrets.prefixes), [var.cluster_name])) == 0
    )
    error_message = "kube.external_secrets with kube.crossplane on AWS needs the cluster's region: the module's role is scoped to secrets in that region and its Pod Identity association is regional. Pass region to the bootstrap module (the aws root wires var.aws.region)."
  }

  # values is free-form on purpose, minus one rule: no secret material. What a
  # client writes there ends up in the OpenTofu state and in a ConfigMap on
  # the cluster. ESO's chart takes no credential of its own — a store's
  # credentials are a Secret its auth block names — so the places one could
  # still be smuggled in are refused: a Secret among extraObjects, and an
  # extraEnv entry of any of the three pods whose name says it carries one
  # and whose value is a literal (valueFrom is fine). AWS_SECRETSMANAGER_ENDPOINT
  # is an endpoint, not a credential, and passes.
  validation {
    condition = (
      !can(var.kube.external_secrets.values)
      || !can(keys(var.kube.external_secrets.values))
      || (
        !anytrue(try([for o in var.kube.external_secrets.values.extraObjects : try(o.kind == "Secret", false)], []))
        && alltrue([
          for e in concat(
            try(tolist(var.kube.external_secrets.values.extraEnv), []),
            try(tolist(var.kube.external_secrets.values.webhook.extraEnv), []),
            try(tolist(var.kube.external_secrets.values.certController.extraEnv), []),
          ) :
          !(can(e.value) && can(regex("(?i)(secret_?access|client_?secret|password|passwd|token|api_?key|access_?key|private_?key|credential)", try(e.name, ""))))
        ])
      )
    )
    error_message = "kube.external_secrets.values must not carry secrets: a Secret in extraObjects, and an extraEnv entry (extraEnv, webhook.extraEnv, certController.extraEnv) with a literal value whose name looks like a credential (AWS_SECRET_ACCESS_KEY, *_TOKEN, …), are refused. Put them in a Secret in the external-secrets namespace and name it in kube.external_secrets.values_secret — or, for a store's credentials, in a Secret the store's auth block references."
  }

  validation {
    condition     = !can(var.kube.external_secrets.values_secret) || try(var.kube.external_secrets.values_secret == "" || can(regex("^[a-z0-9]([-a-z0-9.]{0,251}[a-z0-9])?$", var.kube.external_secrets.values_secret)), true)
    error_message = "kube.external_secrets.values_secret must be empty or a valid Kubernetes Secret name (lowercase RFC 1123 subdomain)."
  }

  # --- velero — docs/catalog/velero.md --------------------------------------
  # On aws and gcp the module's bucket and its access are Crossplane managed
  # resources: with Crossplane off there is neither, and Velero would run
  # with nowhere to write. A client's own bucket and identity are out of
  # scope in v1.
  validation {
    condition     = !can(keys(var.kube)) || !contains(["aws", "gcp"], var.cloud) || !try(var.kube.velero.enabled, false) || try(var.kube.crossplane.enabled, false) == true
    error_message = var.cloud == "gcp" ? "kube.velero on gcp needs kube.crossplane.enabled = true: the module's bucket and its IAM binding are Crossplane managed resources (docs/catalog/velero.md). Turn Crossplane on, and allow roles/storage.objectAdmin in the foundations' crossplane.allowed_roles." : "kube.velero on aws needs kube.crossplane.enabled = true: the module's bucket and its IAM role are Crossplane managed resources (docs/catalog/velero.md). Turn Crossplane on, and allow s3 in the foundations' aws.crossplane.allowed_services."
  }

  # The bucket is regional, and on aws so is the Pod Identity association.
  validation {
    condition     = !can(keys(var.kube)) || !contains(["aws", "gcp"], var.cloud) || !try(var.kube.velero.enabled, false) || var.region != ""
    error_message = var.cloud == "gcp" ? "kube.velero on gcp needs the cluster's region: the bucket is regional. Pass region to the bootstrap module (the gcp root wires the foundations' region output)." : "kube.velero on aws needs the cluster's region: the bucket and the module's Pod Identity association are regional. Pass region to the bootstrap module (the aws root wires var.aws.region)."
  }

  # Autopilot refuses the hostPath mount of the kubelet's pods directory the
  # node-agent reads volumes through: its DaemonSet would never schedule.
  # On gcp every volume is a PD, backed up as a CSI snapshot.
  validation {
    condition     = !can(keys(var.kube)) || var.cloud != "gcp" || try(var.kube.velero.node_agent, false) != true
    error_message = "kube.velero.node_agent is refused on gcp: Autopilot forbids the node-agent's hostPath, so its DaemonSet would never run. Persistent Disk volumes are backed up as CSI snapshots, which need no node-agent."
  }

  # policies: each entry becomes one Schedule named <frequency>-<retention>,
  # selecting the two labels an application's chart sets. Both values are
  # label values and part of an object name; retention is the TTL, in hours
  # or days; schedule is a five-field cron expression, as Velero takes it.
  validation {
    condition = !can(var.kube.velero.policies) || try(alltrue([
      for p in tolist(var.kube.velero.policies) :
      can(keys(p))
      && length(setsubtract(keys(p), ["frequency", "retention", "schedule"])) == 0
      && length(keys(p)) == 3
      && can(regex("^[a-z0-9]([a-z0-9-]{0,22}[a-z0-9])?$", p.frequency))
      && can(regex("^[1-9][0-9]{0,4}(h|d)$", p.retention))
      && can(regex("^\\S+( \\S+){4}$", p.schedule))
    ]), false)
    error_message = "kube.velero.policies must be a list of { frequency, retention, schedule }: frequency 1 to 24 lowercase letters, digits or dashes (such as daily), retention a whole number of hours or days (such as 48h or 30d), schedule a five-field cron expression (such as \"0 2 * * *\"), and nothing else."
  }

  validation {
    condition = !can(var.kube.velero.policies) || try(
      length(distinct([for p in tolist(var.kube.velero.policies) : "${p.frequency}-${p.retention}"])) == length(tolist(var.kube.velero.policies)),
      true,
    )
    error_message = "kube.velero.policies names a (frequency, retention) pair twice: each pair is one Schedule, named after it."
  }

  # values is free-form on purpose, minus one rule: no secret material. Velero's
  # chart turns credentials.secretContents into a Secret and
  # credentials.extraEnvVars into environment variables of every pod, and
  # extraObjects may hold a Secret. A Secret the client creates is named
  # through credentials.existingSecret, which carries no secret itself.
  validation {
    condition = (
      !can(var.kube.velero.values)
      || !can(keys(var.kube.velero.values))
      || (
        length(try(keys(var.kube.velero.values.credentials.secretContents), [])) == 0
        && length(try(keys(var.kube.velero.values.credentials.extraEnvVars), [])) == 0
        && !anytrue(try([for o in var.kube.velero.values.extraObjects : try(o.kind == "Secret", false)], []))
        && alltrue([
          for e in try(tolist(var.kube.velero.values.configuration.extraEnvVars), []) :
          !(can(e.value) && can(regex("(?i)(secret|password|passwd|token|api_?key|access_?key|private_?key)", try(e.name, ""))))
        ])
      )
    )
    error_message = "kube.velero.values must not carry secrets: credentials.secretContents, credentials.extraEnvVars, a Secret in extraObjects and a configuration.extraEnvVars entry with a literal value named like a credential are refused. Create the Secret in the velero namespace and name it in credentials.existingSecret, or put chart values in a Secret named in kube.velero.values_secret."
  }

  validation {
    condition     = !can(var.kube.velero.values_secret) || try(var.kube.velero.values_secret == "" || can(regex("^[a-z0-9]([-a-z0-9.]{0,251}[a-z0-9])?$", var.kube.velero.values_secret)), true)
    error_message = "kube.velero.values_secret must be empty or a valid Kubernetes Secret name (lowercase RFC 1123 subdomain)."
  }

  validation {
    condition     = !can(var.kube.metrics_server.values_secret) || try(var.kube.metrics_server.values_secret == "" || can(regex("^[a-z0-9]([-a-z0-9.]{0,251}[a-z0-9])?$", var.kube.metrics_server.values_secret)), true)
    error_message = "kube.metrics_server.values_secret must be empty or a valid Kubernetes Secret name (lowercase RFC 1123 subdomain)."
  }

  # values is free-form, minus the one flag that lowers what the module checks.
  # --kubelet-insecure-tls makes metrics-server skip the kubelets' serving
  # certificates, so it would hand its own token to anything answering as a
  # kubelet. The socle owns the nodes: a certificate that does not validate is
  # the socle's to fix. The chart reads defaultArgs and args, so both lists are
  # checked, and the flag is refused in any form. The API server to
  # metrics-server settings (tls.*, apiService.*) stay free: they can only
  # raise the check.
  validation {
    condition = (
      !can(var.kube.metrics_server.values)
      || !can(keys(var.kube.metrics_server.values))
      || alltrue([
        for a in concat(
          try([for x in tolist(var.kube.metrics_server.values.defaultArgs) : tostring(x)], []),
          try([for x in tolist(var.kube.metrics_server.values.args) : tostring(x)], [])
        ) :
        !can(regex("^--kubelet-insecure-tls(=|$)", a))
      ])
    )
    error_message = "kube.metrics_server.values must not set --kubelet-insecure-tls: it disables verification of kubelet certificates, so metrics-server would present its credentials to anyone impersonating a kubelet. The socle owns the nodes, and a certificate that does not validate is a socle bug to fix, not a client's to work around."
  }

  # --- karpenter — docs/catalog/karpenter.md ---------------------------------

  # Its role and its interruption queue are Crossplane managed resources: with
  # Crossplane off it would install a controller that can launch nothing.
  validation {
    condition     = !can(keys(var.kube)) || !try(var.kube.karpenter.enabled, false) || try(var.kube.crossplane.enabled, false) == true
    error_message = "kube.karpenter needs kube.crossplane.enabled = true: its IAM role, Pod Identity association and interruption queue are Crossplane managed resources (docs/catalog/karpenter.md). Turn Crossplane on, and allow ec2, ssm, pricing, sqs and eks in the foundations' aws.crossplane.allowed_services."
  }

  validation {
    condition     = !can(keys(var.kube)) || !try(var.kube.karpenter.enabled, false) || var.region != ""
    error_message = "kube.karpenter needs the cluster's region: its queue, its EventBridge rules and its Pod Identity association are regional. Pass region to the bootstrap module (the aws root wires var.aws.region)."
  }

  # The same rules for both NodePools, private_pool and public_pool.
  validation {
    condition = alltrue([for p in ["private_pool", "public_pool"] : !can(var.kube.karpenter[p].capacity_types) || try(
      length(tolist(var.kube.karpenter[p].capacity_types)) > 0
      && length(distinct(tolist(var.kube.karpenter[p].capacity_types))) == length(tolist(var.kube.karpenter[p].capacity_types))
      && alltrue([for c in tolist(var.kube.karpenter[p].capacity_types) : contains(["spot", "on-demand"], c)]),
      false
    )])
    error_message = "kube.karpenter.private_pool.capacity_types and public_pool.capacity_types must list spot, on-demand or both, each once."
  }

  validation {
    condition = alltrue([for p in ["private_pool", "public_pool"] : !can(var.kube.karpenter[p].architectures) || try(
      length(tolist(var.kube.karpenter[p].architectures)) > 0
      && length(distinct(tolist(var.kube.karpenter[p].architectures))) == length(tolist(var.kube.karpenter[p].architectures))
      && alltrue([for a in tolist(var.kube.karpenter[p].architectures) : contains(["arm64", "amd64"], a)]),
      false
    )])
    error_message = "kube.karpenter.private_pool.architectures and public_pool.architectures must list arm64, amd64 or both, each once: the values of kubernetes.io/arch."
  }

  validation {
    condition     = alltrue([for p in ["private_pool", "public_pool"] : !can(var.kube.karpenter[p].cpu) || try(var.kube.karpenter[p].cpu >= 1 && floor(var.kube.karpenter[p].cpu) == var.kube.karpenter[p].cpu, false)])
    error_message = "kube.karpenter.private_pool.cpu and public_pool.cpu must be a whole number of vCPU, at least 1: the ceiling of all the NodePool's nodes together."
  }

  validation {
    condition     = alltrue([for p in ["private_pool", "public_pool"] : !can(var.kube.karpenter[p].memory) || try(can(regex("^[1-9][0-9]*(Mi|Gi|Ti)$", var.kube.karpenter[p].memory)), false)])
    error_message = "kube.karpenter.private_pool.memory and public_pool.memory must be a Kubernetes quantity in Mi, Gi or Ti, such as 128Gi: the ceiling of all the NodePool's nodes together."
  }

  validation {
    condition     = alltrue([for p in ["private_pool", "public_pool"] : !can(var.kube.karpenter[p].consolidate_after) || try(can(regex("^([0-9]+h)?([0-9]+m)?([0-9]+s)?$", var.kube.karpenter[p].consolidate_after)) && var.kube.karpenter[p].consolidate_after != "", false)])
    error_message = "kube.karpenter.private_pool.consolidate_after and public_pool.consolidate_after must be a duration in hours, minutes and seconds, such as 1m or 1h30m."
  }

  # AL2023 only: the bootstrap nodes' AMI family, the one whose nodeadm
  # Karpenter configures for this cluster, Cilium is proven on, and the
  # public EC2NodeClass's NodeConfig is written for.
  validation {
    condition     = alltrue([for p in ["private_pool", "public_pool"] : !can(var.kube.karpenter[p].ami) || try(can(regex("^al2023@(latest|v[0-9]{8})$", var.kube.karpenter[p].ami)), false)])
    error_message = "kube.karpenter.private_pool.ami and public_pool.ami must be an AL2023 alias, al2023@latest or al2023@v<YYYYMMDD> such as al2023@v20261001: the bootstrap nodes' AMI family."
  }

  # values is free-form, minus credentials: the controller takes its AWS
  # access from Pod Identity, and an access key in controller.env would land
  # in the state and in a ConfigMap. Its name says it whatever the case.
  validation {
    condition = (
      !can(var.kube.karpenter.values)
      || !can(keys(var.kube.karpenter.values))
      || alltrue([
        for e in try(tolist(var.kube.karpenter.values.controller.env), []) :
        !(can(e.value) && can(regex("(?i)(secret|password|passwd|token|credential|api_?key|access_?key|private_?key)", try(e.name, ""))))
      ])
    )
    error_message = "kube.karpenter.values must not carry secrets: a controller.env entry with a literal value named like a password, token, secret, credential or key is refused. Its AWS access is its Pod Identity role; anything else goes in a Secret named in kube.karpenter.values_secret."
  }

  validation {
    condition     = !can(var.kube.karpenter.values_secret) || try(var.kube.karpenter.values_secret == "" || can(regex("^[a-z0-9]([-a-z0-9.]{0,251}[a-z0-9])?$", var.kube.karpenter.values_secret)), true)
    error_message = "kube.karpenter.values_secret must be empty or a valid Kubernetes Secret name (lowercase RFC 1123 subdomain)."
  }
}

# ---------------------------------------------------------------------------
# Cilium — cilium.tf and docs/architecture/cilium-before-flux.md
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

variable "eks_addons" {
  description = <<-EOT
    The EKS-managed add-ons the socle installs on aws once the nodes run, as
    `{ pod_identity_agent, ebs_csi, efs_csi, snapshot_controller }`, every
    key optional:
    `pod_identity_agent` (true) is what hands every Pod Identity association
    its credentials — Crossplane's AWS providers included — and flux-operator
    waits for it; `ebs_csi` (true) is the block-storage driver, with its own
    role; `efs_csi` (false) the RWX one, with its own role. Both drivers need
    the agent. `snapshot_controller` (true) is the CSI snapshot controller
    and its CRDs, what the velero module's EBS snapshots need. Refused on
    every cloud but aws. Versions pinned in eks_addons.tf.
  EOT
  type        = any
  default     = {}
  nullable    = false

  validation {
    condition     = can(keys(var.eks_addons))
    error_message = "eks_addons must be an object of attributes."
  }

  validation {
    condition     = !can(keys(var.eks_addons)) || alltrue([for a in keys(var.eks_addons) : contains(keys(local.eks_addons_schema), a)])
    error_message = "eks_addons: unknown attribute. Allowed: ${join(", ", keys(local.eks_addons_schema))}."
  }

  validation {
    condition     = !can(keys(var.eks_addons)) || alltrue([for a, x in var.eks_addons : !contains(keys(local.eks_addons_schema), a) || x == true || x == false])
    error_message = "eks_addons: every attribute is a bool, true to install the add-on."
  }

  validation {
    condition     = !can(keys(var.eks_addons)) || length(keys(var.eks_addons)) == 0 || var.cloud == "aws"
    error_message = "eks_addons is only configurable on aws: they are EKS-managed add-ons, and other clouds ship their own drivers and workload identity."
  }

  validation {
    condition     = !can(keys(var.eks_addons)) || try(merge(local.eks_addons_schema, var.eks_addons).pod_identity_agent || !(merge(local.eks_addons_schema, var.eks_addons).ebs_csi || merge(local.eks_addons_schema, var.eks_addons).efs_csi), true)
    error_message = "eks_addons: ebs_csi and efs_csi get their credentials from the Pod Identity Agent; they cannot be installed with pod_identity_agent = false."
  }
}

variable "cluster_network" {
  description = <<-EOT
    What Cilium needs to know about the cluster, from the foundations'
    outputs, never from the client: `api_endpoint`, the API server as EKS
    returns it (https://host) or AKS does (a bare FQDN), for kube-proxy
    replacement; `service_cidr`, the service range, whose `.10` is CoreDNS's
    address on aws; `pod_cidr`, where pods take their addresses: on aws the
    VPC's CIDR (ENI IPAM), outside which Cilium masquerades, on azure
    Cilium's pool, the VNet holding nodes only. Required wherever the socle
    installs Cilium, ignored elsewhere.
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
    condition     = !(local.cilium_installed && var.cloud == "aws") || try(can(cidrhost(var.cluster_network.pod_cidr, 0)), false)
    error_message = "cluster_network.pod_cidr is required on aws: the VPC's CIDR, which pods take their addresses from and outside which Cilium masquerades. Pass the foundations' vpc_cidr output (the aws root wires it)."
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

variable "gateway_certificate_arn" {
  description = <<-EOT
    On aws, the ACM certificate the shared Gateways' load balancers terminate
    TLS with — the foundations' gateway_certificate_arn output, never the
    client's. Null or empty on aws means no shared Gateway, and no route
    attached to one. Unknown at plan on the apply that issues it, which is
    why nothing validates it here. Ignored elsewhere.
  EOT
  type        = string
  default     = null
}

variable "gateway_certificate_map" {
  description = <<-EOT
    On gcp, the Certificate Manager map the public shared Gateway's global
    load balancer terminates TLS with — the foundations'
    gateway_certificate_map output, never the client's. Null or empty on gcp
    means no shared Gateway, and no route attached to one. Unknown at plan on
    the apply that creates it, which is why nothing validates it here.
    Ignored elsewhere.
  EOT
  type        = string
  default     = null
}

variable "gateway_regional_certificate" {
  description = <<-EOT
    On gcp, the regional Certificate Manager certificate the private shared
    Gateway's internal load balancer terminates TLS with — the foundations'
    gateway_regional_certificate output, never the client's. Null or empty
    on gcp means no shared Gateway either: a private listener without it
    would never be programmed. Unknown at plan on the apply that creates it,
    which is why nothing validates it here. Ignored elsewhere.
  EOT
  type        = string
  default     = null
}

variable "schedulable_nodes" {
  description = <<-EOT
    How many nodes the foundations give the cluster before this module
    starts — on aws, the bootstrap node group's size. Everything but Cilium
    waits for it: Cilium's DaemonSet is what makes those nodes Ready, so it
    is installed beside them, and CoreDNS and the Flux operator, the first
    releases that need a scheduled pod, come after. Zero fails the plan with
    that reason, instead of Helm waiting helm_timeout_seconds for a node.
    Null skips the check, on a cluster whose compute this module cannot see.
  EOT
  type        = number
  default     = null
}

# ---------------------------------------------------------------------------
# What the cluster pulls — docs/architecture/distribution.md
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

  # Flux matches these as regexes, unanchored: `.*`, or a subject without
  # its `$`, accepts any workflow of any repository — or of a fork whose
  # name merely starts with ours. Both ends anchored, and something between
  # them that is not only a wildcard.
  validation {
    condition = alltrue([
      for p in [var.cosign_identity.issuer, var.cosign_identity.subject] :
      startswith(p, "^") && endswith(p, "$") && !endswith(p, "\\$") && !can(regex("^\\^[.*+?]*\\$$", p))
    ])
    error_message = "cosign_identity issuer and subject must each be anchored, starting with ^ and ending with $, and name something: an unanchored or wildcard-only pattern accepts any signer."
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
  description = "Flux version the operator installs and keeps converged. 2.x tracks the latest 2 series the operator ships (its embedded distribution, so operator_version bounds it); 2.y.x the latest patch of 2.y; an exact 2.y.z pins it."
  type        = string
  default     = "2.x"
  nullable    = false

  validation {
    condition     = can(regex("^2\\.(x|(0|[1-9][0-9]*)\\.(x|0|[1-9][0-9]*))$", var.flux_version))
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
