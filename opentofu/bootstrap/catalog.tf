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
    # Gateway API: the standard-channel CRDs, and one implementation per cloud
    # behind the class name `socle`. The defaults differ per cloud and are the
    # table below, not the client's to know: GKE ships the CRDs and a managed
    # controller, the others get Envoy Gateway until Cilium implements it
    # (docs/catalog/gateway-api.md). install_crds and implementation are
    # validated per cloud in variables.tf.
    gateway_api = {
      enabled        = true
      install_crds   = local.gateway_api_defaults[var.cloud].install_crds
      implementation = local.gateway_api_defaults[var.cloud].implementation
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
  # Read by CI only until the first cloud-bound module lands; the plan-time
  # validation of kube against it arrives then, with the test that trips it.
  # tflint-ignore: terraform_unused_declarations
  catalog_clouds = {}

  # gateway_api per cloud: who implements it, and whether the socle installs
  # the CRDs. One line to flip when Cilium takes over a cloud (implementation
  # = "cilium", install_crds = false — Cilium's operator needs the CRDs before
  # it starts, so its bootstrap release owns them). `managed` is GKE's own
  # controller and CRDs: the module installs nothing there. The second map
  # is what a client may choose on each cloud; anything else is refused at
  # plan.
  gateway_api_defaults = {
    aws      = { implementation = "envoy-gateway", install_crds = true }
    azure    = { implementation = "envoy-gateway", install_crds = true }
    gcp      = { implementation = "managed", install_crds = false }
    scaleway = { implementation = "envoy-gateway", install_crds = true }
  }
  gateway_api_implementations = {
    aws      = ["cilium", "envoy-gateway"]
    azure    = ["cilium", "envoy-gateway"]
    gcp      = ["managed"]
    scaleway = ["envoy-gateway"]
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
