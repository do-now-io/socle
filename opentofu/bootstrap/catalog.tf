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
    # The Gateway API standard CRDs, from upstream pinned by commit, and on
    # the clouds where the socle runs Cilium, the `cilium` GatewayClass and
    # the one operator restart that turns Cilium's controller on
    # (docs/catalog/cilium.md §4). Not on gcp, where GKE owns the CRDs and
    # the controller. No chart, so no values/values_secret. Disabling it
    # removes the Flux objects and orphans the CRDs: every Gateway survives.
    gateway_api = {
      enabled = true
    }
    # v1: proves the pipeline end to end. A real module reads exactly like it.
    hello = {
      enabled  = true
      replicas = 1
      message  = "hello from socle"
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
