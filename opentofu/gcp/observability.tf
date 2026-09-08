# Upgrade notifications and the cost attribution dataset —
# docs/gcp/managed-scope.md and docs/gcp/cloud-observability.md.
#
# Deliberately absent: alert policies, dashboards, uptime checks and metrics
# scopes. Alerting and dashboards are catalog objects so that four clouds
# share one definition, and Cloud Monitoring alert policies become billable on
# 1 September 2027.

# GKE publishes UpgradeAvailableEvent, UpgradeEvent, SecurityBulletinEvent and
# UpgradeInfoEvent here, so automation can react instead of polling the
# release notes.
resource "google_pubsub_topic" "upgrade_notifications" {
  count = var.enable_upgrade_notifications ? 1 : 0

  project = var.project_id
  name    = "${var.cluster_name}-gke-upgrades"
  labels  = local.labels
}

# The detailed usage cost export is the cost attribution source: resource
# level, and the only export that carries the cluster, namespace and workload
# labels that cost_management_config adds.
#
# The module creates the dataset. It cannot create the export itself: Google
# exposes no API for configuring a billing export destination, so linking the
# billing account to this dataset is a Cloud Console step. It is the one place
# where a consumer's apply does not finish the job, and it is documented
# rather than hidden.
resource "google_bigquery_dataset" "billing_export" {
  count = var.billing_export_dataset_id == null ? 0 : 1

  project     = var.project_id
  dataset_id  = var.billing_export_dataset_id
  location    = var.billing_export_dataset_location
  description = "Destination for the detailed Cloud Billing export. Link the billing account to it in the Cloud Console — Google exposes no API for that step."
  labels      = local.labels

  # Cost data is the audit trail for what a cluster consumed. Deleting the
  # dataset with tables in it has to be a deliberate act, not a side effect of
  # a destroy.
  delete_contents_on_destroy = false
}
