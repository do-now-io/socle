# Identities — docs/scaleway/managed-scope.md.
#
# This is the file where Scaleway costs the socle something the other three
# clouds do not. GKE has Workload Identity Federation, EKS has Pod Identity,
# AKS has Workload Identity. Scaleway has none: a Pod that calls the Scaleway
# API carries a long-lived API key, and there is no trust relationship a
# Kubernetes ServiceAccount token can be exchanged against.
#
# So this module produces a credential. Every other foundations module refuses
# to, and the conformance checklist says modules authenticate through ambient
# credentials or federation. **This is the recorded exception**, not an
# oversight: the alternative is no in-cluster provisioning on Scaleway at all.
# The key is a sensitive output, never written to a file by the module, and
# the two mitigations below are what make it survivable.

resource "scaleway_iam_application" "crossplane" {
  name        = "${var.cluster_name}-crossplane"
  description = "In-cluster Crossplane provider for the ${var.cluster_name} socle cluster."
  tags        = local.tags
}

# Mitigation one: the policy is scoped to a single Project and to the
# permission sets the client actually needs. Scaleway has no per-resource
# conditions outside IAM, Key Manager and Secret Manager, so the Project is the
# only boundary available — which is why the module takes a required
# project_id and why one environment means one Project.
#
# Mitigation two: a request-level condition binds the key to a source address.
# Those conditions do work on every product, and under full isolation the only
# address a node can present is a Public Gateway's. A leaked key is then
# useless anywhere else.
resource "scaleway_iam_policy" "crossplane" {
  name           = "${var.cluster_name}-crossplane"
  description    = "Scoped access for the in-cluster Crossplane provider of ${var.cluster_name}."
  application_id = scaleway_iam_application.crossplane.id
  tags           = local.tags

  rule {
    project_ids          = [var.project_id]
    permission_set_names = var.crossplane_permission_sets

    condition = format(
      "request.ip in [%s]",
      join(", ", [
        for c in(length(var.crossplane_allowed_cidrs) > 0 ? var.crossplane_allowed_cidrs : local.gateway_egress_cidrs) :
        "'${c}'"
      ])
    )
  }
}

resource "scaleway_iam_api_key" "crossplane" {
  application_id     = scaleway_iam_application.crossplane.id
  description        = "Socle foundations — in-cluster Crossplane provider for ${var.cluster_name}."
  default_project_id = var.project_id

  # An expiry is the only thing that forces rotation to actually happen.
  # Changing it replaces the key, so the socle has to be able to pick up a new
  # one — which is the capability the factory owns, and the reason this is a
  # variable rather than a hardcoded year.
  expires_at = var.crossplane_key_expires_at
}
