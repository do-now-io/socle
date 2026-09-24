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
  # Read by CI only until the first cloud-bound module lands; the plan-time
  # validation of kube against it arrives then, with the test that trips it.
  # tflint-ignore: terraform_unused_declarations
  catalog_clouds = {}

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
