# Socle foundations for Google Cloud.
#
# One flat root module: network, GKE cluster and identities. It provisions an
# empty-shell Autopilot cluster and the identities the Flux-pulled socle needs,
# then steps away. Everything above that — the catalog, the observability
# stack, application infrastructure — arrives through the socle OCI artifact
# and Crossplane.
#
# Every default here traces back to a research document under docs/gcp/.
# Resources live in network.tf, cluster.tf, iam.tf and observability.tf.

locals {
  # Stamped onto every billable resource so cost can be attributed and orphans
  # can be found. Bumped with the module's own tag.
  socle_version = "0.1.0-dev"

  # The standard label set. Google Cloud label values take lowercase letters,
  # digits, dashes and underscores only, which is why the version is
  # normalised.
  labels = merge(
    {
      owner         = var.owner
      environment   = var.environment
      socle-version = replace(local.socle_version, ".", "-")
    },
    var.additional_labels,
  )

  # Networks and subnetworks are referenced by path rather than read through a
  # data source: it keeps the module free of a lookup that would fail on a
  # project where the consumer's network lives elsewhere, and it is what the
  # GKE API accepts.
  network_name = var.create_network ? google_compute_network.socle[0].name : var.network_name
  network_path = "projects/${var.project_id}/global/networks/${local.network_name}"

  subnetwork_name = var.create_subnetwork ? google_compute_subnetwork.socle[0].name : var.subnetwork_name
  subnetwork_path = "projects/${var.project_id}/regions/${var.region}/subnetworks/${local.subnetwork_name}"

  # The Pod range is named after the cluster when the module owns the subnet,
  # and supplied by the consumer when it does not.
  pod_range_name = coalesce(var.pod_range_name, "${var.cluster_name}-pods")

  # Derived, not configurable: Autopilot enforces Workload Identity Federation
  # and the pool name follows the project.
  workload_identity_pool = "${var.project_id}.svc.id.goog"

  crossplane_workload_identity_member = "serviceAccount:${local.workload_identity_pool}[${var.crossplane_service_account_namespace}/${var.crossplane_service_account_name}]"
}
