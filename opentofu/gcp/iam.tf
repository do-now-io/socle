# Identities — docs/gcp/managed-scope.md.
#
# Workload Identity Federation itself has nothing to configure: Autopilot
# pre-configures it and it cannot be disabled. The pool is exposed as an
# output, and what binds a Kubernetes service account to a Google one is left
# to the layer that owns those Kubernetes objects — the in-cluster providers
# arrive through the socle, not through this module.

# Read-only metric access for the central observability cluster. A federated
# principal, never a key — the module refuses to accept a credential as input,
# so there is nothing here to leak.
resource "google_project_iam_member" "observability_reader" {
  for_each = toset(var.observability_reader_members)

  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = each.value
}
