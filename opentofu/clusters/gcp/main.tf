# The socle on Google Cloud, in one apply: the cluster, then Flux and the
# catalog on it.
#
# In the repository the two sources are relative, so this root is what CI
# applies. A client's copy points both at the published module, with the
# version in the source:
#
#   source = "oci://ghcr.io/do-now-io/socle/opentofu-modules//opentofu/gcp?tag=${var.socle_version}"
#   source = "oci://ghcr.io/do-now-io/socle/opentofu-modules//opentofu/bootstrap?tag=${var.socle_version}"
#
# (the modules package, not the socle artifact: one OCI tag cannot carry both
# shapes — PR #15)
#
# Two cases need more than one apply, both documented in README.md: replacing
# the cluster, and destroying it when the runner cannot reach the API.

provider "google" {
  project = var.gcp.project_id
  region  = var.gcp.region
}

# The bootstrap module holds the EKS-managed add-ons, so OpenTofu configures
# the aws provider on every cloud, even with all its resources at count = 0.
# Left unconfigured it would look for credentials and call STS; this stub
# skips every check and makes no network call.
provider "aws" {
  region                      = "us-east-1"
  access_key                  = "unused"
  secret_key                  = "unused"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
}

module "foundations" {
  source = "../../gcp"

  project_id        = var.gcp.project_id
  project_number    = var.gcp.project_number
  region            = var.gcp.region
  cluster_name      = var.gcp.cluster_name
  owner             = var.gcp.owner
  environment       = var.gcp.environment
  additional_labels = var.gcp.additional_labels

  network_name             = var.gcp.network_name
  create_network           = var.gcp.create_network
  create_subnetwork        = var.gcp.create_subnetwork
  subnetwork_name          = var.gcp.subnetwork_name
  pod_range_name           = var.gcp.pod_range_name
  node_range_cidr          = var.gcp.node_range_cidr
  pod_range_cidr           = var.gcp.pod_range_cidr
  proxy_only_range_cidr    = var.gcp.proxy_only_range_cidr
  create_proxy_only_subnet = var.gcp.create_proxy_only_subnet
  create_nat               = var.gcp.create_nat
  subnet_flow_logs_enabled = var.gcp.subnet_flow_logs_enabled

  enable_private_nodes                     = var.gcp.enable_private_nodes
  control_plane_ip_endpoints_enabled       = var.gcp.control_plane_ip_endpoints_enabled
  control_plane_dns_allow_external_traffic = var.gcp.control_plane_dns_allow_external_traffic
  gateway_api_enabled                      = var.gcp.gateway_api_enabled

  release_channel              = var.gcp.release_channel
  maintenance_window           = var.gcp.maintenance_window
  maintenance_exclusions       = var.gcp.maintenance_exclusions
  kubernetes_min_version       = var.gcp.kubernetes_min_version
  enable_upgrade_notifications = var.gcp.enable_upgrade_notifications

  logging_components              = var.gcp.logging_components
  monitoring_components           = var.gcp.monitoring_components
  cost_allocation_enabled         = var.gcp.cost_allocation_enabled
  backup_agent_enabled            = var.gcp.backup_agent_enabled
  billing_export_dataset_id       = var.gcp.billing_export_dataset_id
  billing_export_dataset_location = var.gcp.billing_export_dataset_location
  observability_reader_members    = var.gcp.observability_reader_members

  deletion_protection = var.gcp.deletion_protection

  crossplane = var.gcp.crossplane

  # The certificates the shared Gateways' load balancers terminate TLS with.
  gateway_certificate = var.gcp.gateway_certificate
}

# One line, identical on every cloud. No credential: the exec plugin inside
# obtains a token at call time from the same ambient credentials as the
# google provider above.
provider "helm" {
  kubernetes = module.foundations.helm_kubernetes
}

module "socle" {
  source = "../../bootstrap"

  cloud        = "gcp"
  cluster_name = var.gcp.cluster_name
  environment  = var.gcp.environment
  owner        = var.gcp.owner

  kube                 = local.kube
  region               = module.foundations.region
  socle_version        = var.socle_version
  cosign_identity      = var.cosign_identity
  artifact_url         = var.artifact_url
  artifact_pull_secret = var.artifact_pull_secret

  # Every catalog module's Workload Identity principal names the project by
  # its number, and its pool by the project's id: both from the foundations,
  # the number read from the API unless gcp.project_number gave it.
  project = {
    id     = module.foundations.project_id
    number = module.foundations.project_number
  }

  # The shared Gateways exist only with them: TLS terminates at their load
  # balancers, the public one through the map, the private one through the
  # regional certificate.
  gateway_certificate_map      = module.foundations.gateway_certificate_map
  gateway_regional_certificate = module.foundations.gateway_regional_certificate

  # Autopilot provisions nodes for the pods that ask for them: there is no
  # node group to wait for, and none to count.
  schedulable_nodes = null
}

# The values the root derives for the catalog, so the client does not copy
# one input or output into another. A value the client wrote always wins.
#
# crossplane: when the foundations grant Crossplane its identity
# (gcp.crossplane), the custom role external-dns writes DNS records with is
# what kube.crossplane.dns_records_role takes.
#
# external_dns: when the client already named the domains the Gateways serve
# (gcp.gateway_certificate) and gave Crossplane what external-dns's binding
# needs — the module on and its identity — it is on by default, filtered to
# those domains, a wildcard
# counted once by its apex. Every route on either Gateway is <name>.<domain>,
# so that is the zone it has to write to. The try() hands a kube that is not
# an object to the bootstrap module untouched, for its validations to refuse
# with their own message.
locals {
  # Empty when gcp.crossplane is null: the catalog's own default.
  crossplane_derived = {
    dns_records_role = module.foundations.dns_records_role
  }

  external_dns_derived = (
    var.gcp.gateway_certificate != null
    && try(var.kube.crossplane.enabled, false) == true
    && var.gcp.crossplane != null
  )
  # Through JSON, like kube below: the two branches are objects of different
  # shapes, which a conditional refuses to unify.
  external_dns_defaults = jsondecode(local.external_dns_derived ? jsonencode({ enabled = true, domain_filters = distinct([for d in var.gcp.gateway_certificate.domains : trimprefix(d, "*.")]) }) : "{}")
  # var.kube is `any`: merging a value unknown at plan into it erases the
  # whole result's static type, and the bootstrap module's kind check then
  # sees "known after apply" instead of a kind. jsondecode(jsonencode(...))
  # rebuilds a concrete type from the client's literal values first, so only
  # the new keys can stay unknown.
  kube = try(
    merge(jsondecode(jsonencode(var.kube)), {
      crossplane   = merge(local.crossplane_derived, try(var.kube.crossplane, {}))
      external_dns = merge(local.external_dns_defaults, try(var.kube.external_dns, {}))
    }),
    var.kube,
  )
}

# A warning, not an error: Crossplane without its identity still installs and
# converges, but every binding it is asked to make fails at the Google API.
check "crossplane_has_an_identity" {
  assert {
    condition     = !try(var.kube.crossplane.enabled, false) || var.gcp.crossplane != null
    error_message = "kube.crossplane.enabled is set without gcp.crossplane: the Google Cloud providers run as a principal with no grant, and every binding a module declares will fail. Set gcp.crossplane, or keep Crossplane off."
  }
}
