# Everything needed to bootstrap the Flux-pulled socle, and nothing that is a
# long-lived credential. The cluster CA is marked sensitive; no key material
# is produced by this module at all, so none can be output.

output "cluster_name" {
  description = "Name of the GKE cluster."
  value       = google_container_cluster.socle.name
}

output "cluster_location" {
  description = "Region of the cluster. Regional by default; there is no zonal option."
  value       = google_container_cluster.socle.location
}

output "cluster_dns_endpoint" {
  description = "The control plane's DNS endpoint — the access path the socle and its automation use. Stable for the life of the cluster and authorised by IAM."
  value       = google_container_cluster.socle.control_plane_endpoints_config[0].dns_endpoint_config[0].endpoint
}

output "cluster_endpoint" {
  description = "IP endpoint of the control plane. Empty when IP endpoints are disabled, which is the default."
  value       = google_container_cluster.socle.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate, for building a kubeconfig."
  value       = google_container_cluster.socle.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "oidc_issuer_url" {
  description = "The cluster's OIDC issuer, for federating an external identity provider against this cluster."
  value       = "https://container.googleapis.com/v1/projects/${var.project_id}/locations/${var.region}/clusters/${var.cluster_name}"
}

output "workload_identity_pool" {
  description = "The Workload Identity Federation pool. Autopilot enforces it, so this is derived rather than configured. Grant IAM roles to principals in this pool to give a catalog workload direct resource access."
  value       = local.workload_identity_pool
}

output "workload_identity_principal_prefix" {
  description = "Prefix of a workload's IAM principal identifier. Append ns/NAMESPACE/sa/SERVICEACCOUNT. Note that two clusters in one project produce identical principals for the same namespace and service account."
  value       = "principal://iam.googleapis.com/projects/${var.project_id}/locations/global/workloadIdentityPools/${local.workload_identity_pool}/subject"
}

output "upgrade_notifications_topic" {
  description = "Pub/Sub topic carrying GKE upgrade and security bulletin notifications. Null when notifications are disabled."
  value       = var.enable_upgrade_notifications ? google_pubsub_topic.upgrade_notifications[0].id : null
}

output "network_name" {
  description = "Name of the VPC the cluster is attached to, whether the module created it or not."
  value       = local.network_name
}

output "subnetwork_name" {
  description = "Name of the cluster's subnetwork."
  value       = local.subnetwork_name
}

output "pod_range_name" {
  description = "Name of the secondary range carrying Pod addresses."
  value       = local.pod_range_name
}

output "proxy_only_subnetwork_name" {
  description = "The REGIONAL_MANAGED_PROXY subnetwork regional Gateways draw their proxies from. Null when the module did not create it."
  value       = var.create_proxy_only_subnet ? google_compute_subnetwork.proxy_only[0].name : null
}

output "billing_export_dataset" {
  description = "Reference of the BigQuery dataset waiting for the detailed billing export. Null when none was requested. The billing account still has to be linked to it by hand."
  value       = var.billing_export_dataset_id == null ? null : google_bigquery_dataset.billing_export[0].id
}

output "labels" {
  description = "The standard label set applied to every billable resource this module creates."
  value       = local.labels
}
