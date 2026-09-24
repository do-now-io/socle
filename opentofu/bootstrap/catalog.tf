# The catalog schema. One entry per module; its defaults ARE its schema: the
# attribute names a client may set, and what each is when he does not. The
# validations in variables.tf refuse anything outside this map, and
# local.modules merges the client's values over it so that every module and
# every attribute is present in what reaches the cluster — the artifact's
# templates test values, never presence.
#
# Adding a module to the catalog is an entry here, a folder under oci/catalog/
# and a line in every oci/clusters/<cloud>/kustomization.yaml it exists on
# (catalog_clouds below says which) — in the same release. They travel
# together because module and artifact share socle_version.
locals {
  catalog = {
    # external-dns: publishes DNS records for Services, Ingresses and Gateway
    # API HTTPRoutes into the cloud's zone (Route 53, Cloud DNS, Azure DNS,
    # Scaleway DNS — the template picks the provider). Off by default: it
    # needs a zone to publish into, which has no default, and a credential the
    # socle does not provide yet — see docs/catalog/external-dns.md. When
    # enabled, domain_filters is required (variables.tf). txt_owner_id
    # defaults to the cluster name so two clusters never fight over one zone.
    external_dns = {
      enabled        = false
      domain_filters = []
      policy         = "upsert-only"
      txt_owner_id   = var.cluster_name
      # docs/flux-catalog.md §6: free-form chart values, and the name of a
      # Secret the client creates in the external-dns namespace for what must
      # not reach the OpenTofu state.
      values        = {}
      values_secret = ""
    }
    # v1: proves the pipeline end to end. A real module reads exactly like it.
    hello = {
      enabled  = true
      replicas = 1
      message  = "hello from socle"
    }
    # The Gateway API standard CRDs, from upstream pinned by commit, and on
    # the clouds where the socle runs Cilium, the `cilium` GatewayClass and
    # the one operator restart that turns Cilium's controller on
    # (docs/catalog/cilium.md §4). Not on gcp, where GKE owns the CRDs and
    # the controller. No chart, so no values/values_secret. Disabling it
    # removes the Flux objects and orphans the CRDs: every Gateway survives.
    gateway_api = {
      enabled = true
    }
    # The tooling through which every catalog module carries its own cloud
    # IAM: Crossplane and, per cloud, the IAM providers and their
    # ProviderConfig (on AWS: provider-aws-iam and -eks, on Pod Identity). A
    # module that needs a cloud service declares its own role in its own
    # ResourceSet (docs/catalog/crossplane.md); nothing here names a module.
    # Off by default until the first module that needs cloud access defaults
    # on — that module's PR flips this too.
    # values is the client's own chart values, merged over the socle's, his
    # winning; secrets are refused there and go in values_secret, a Secret he
    # creates in crossplane-system with a values.yaml key, never read by
    # OpenTofu. permissions_boundary (AWS) is the policy every module's role
    # must carry — the client root wires it from the foundations'
    # crossplane_permissions_boundary_arn; empty means the roles are created
    # without one, which the foundations' Crossplane identity refuses.
    #
    # WARNING — turning it off does not delete what it provisioned. The
    # namespace and the release go; the CRDs and the crossplane-no-usages
    # webhook stay, and so does every module role still declared, orphaned
    # in the cloud with nothing left to reconcile or delete it. Turn those
    # modules off first, wait for their roles to be gone, then
    # enabled = false.
    crossplane = {
      enabled              = false
      values               = {}
      values_secret        = ""
      permissions_boundary = ""
    }
  }

  # Which clouds a module exists on. Absent = every cloud. A module listed
  # here is offered only by the oci/clusters/<cloud>/ overlays named, and
  # .github/scripts/check-catalog-clouds.sh fails CI when an overlay and this
  # map disagree — the overlay is what deploys, this map is what the client
  # may configure, and they must say the same thing. The script reads this
  # block by shape: one `name = ["cloud", ...]` per line.
  # var.kube refuses at plan a module this map does not offer on var.cloud.
  catalog_clouds = {
    gateway_api = ["aws", "azure", "scaleway"]
  }

  modules = { for m, d in local.catalog : m => merge(d, try(var.kube[m], {})) }

  # jsonencode's first character tells a value's kind without a type()
  # function: `"` string, `[` list, `{` object, t/f bool, n null, else number.
  json_kinds = {
    "\"" = "string"
    "["  = "list"
    "{"  = "object"
    "t"  = "bool"
    "f"  = "bool"
    "n"  = "null"
  }
}
