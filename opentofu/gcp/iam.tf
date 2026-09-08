# Identities — docs/gcp/managed-scope.md.
#
# Workload Identity Federation itself has nothing to configure: Autopilot
# pre-configures it and it cannot be disabled. What does need building is the
# one identity that cannot use a federated principal directly.
#
# The Upbound GCP provider's InjectedIdentity resolves Application Default
# Credentials through a Google service account named in the annotation
# iam.gke.io/gcp-service-account on the provider's Kubernetes service account.
# So a Google service account is required, and this module creates it and
# binds it to that Kubernetes identity. No key is ever issued.

resource "google_service_account" "crossplane" {
  project      = var.project_id
  account_id   = "${var.cluster_name}-crossplane"
  display_name = "Crossplane GCP provider (${var.cluster_name})"
  description  = "Assumed by the in-cluster Crossplane GCP provider through Workload Identity Federation. Managed by the socle foundations module."
}

resource "google_service_account_iam_member" "crossplane_workload_identity" {
  service_account_id = google_service_account.crossplane.name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.crossplane_workload_identity_member
}

# Empty by default. The catalog does not exist yet, so any list of roles
# written today would be a guess presented as a recommendation.
resource "google_project_iam_member" "crossplane" {
  for_each = toset(var.crossplane_project_roles)

  project = var.project_id
  role    = each.value
  member  = google_service_account.crossplane.member
}

# Read-only metric access for the central observability cluster. A federated
# principal, never a key — the module refuses to accept a credential as input,
# so there is nothing here to leak.
resource "google_project_iam_member" "observability_reader" {
  for_each = toset(var.observability_reader_members)

  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = each.value
}
