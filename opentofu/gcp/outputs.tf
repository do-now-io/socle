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
  description = "Prefix of a workload's IAM principal identifier, naming the project by its number as Workload Identity Federation requires. Append /ns/NAMESPACE/sa/SERVICEACCOUNT. Note that two clusters in one project produce identical principals for the same namespace and service account."
  value       = local.workload_identity_principal_prefix
}

output "project_id" {
  description = "The project the cluster lives in — half of every workload's principal, with project_number."
  value       = var.project_id
}

output "project_number" {
  description = "The project's number, which a Workload Identity Federation principal names the project by."
  value       = local.project_number
}

output "region" {
  description = "Region of the cluster, and of the internal Gateway's regional certificate."
  value       = var.region
}

output "crossplane_principal" {
  description = "The federated principal the catalog's crossplane module's GCP providers run as (crossplane-system/provider-gcp). Null when crossplane is not set."
  value       = var.crossplane == null ? null : local.crossplane_principal
}

output "crossplane_dns_zones" {
  description = "The Cloud DNS managed zones Crossplane may bind external-dns on — what the bootstrap module hands the catalog. Empty when crossplane is not set."
  value       = try(var.crossplane.dns_zones, [])
}

output "dns_zone_lister_role" {
  description = "Full name of the custom role that lets external-dns list the project's zones, always among the roles Crossplane may grant. Built from its ID, so known on the first plan. Empty when crossplane is not set."
  value       = local.dns_zone_lister_role
}

output "gateway_certificate_map" {
  description = "Name of the Certificate Manager map the public Gateway's networking.gke.io/certmap annotation takes — what the bootstrap module's gateway_certificate_map takes. Empty when gateway_certificate is not set."
  value       = var.gateway_certificate == null ? "" : google_certificate_manager_certificate_map.gateway[0].name
}

output "gateway_regional_certificate" {
  description = "Name of the regional Certificate Manager certificate the internal Gateway's HTTPS listener takes, in its networking.gke.io/cert-manager-certs TLS option — what the bootstrap module's gateway_regional_certificate takes. Empty when gateway_certificate is not set."
  value       = var.gateway_certificate == null ? "" : google_certificate_manager_certificate.gateway_regional[0].name
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

output "helm_kubernetes" {
  description = "Drop-in value for the helm provider's kubernetes attribute, so a root configures it in one line. Uses the DNS endpoint, the only one enabled by default. Carries no credential: gke-gcloud-auth-plugin obtains a short-lived token from the caller's ambient gcloud credentials at call time."
  value = {
    host                   = "https://${google_container_cluster.socle.control_plane_endpoints_config[0].dns_endpoint_config[0].endpoint}"
    cluster_ca_certificate = base64decode(google_container_cluster.socle.master_auth[0].cluster_ca_certificate)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "gke-gcloud-auth-plugin"
      args        = []
    }
  }
  sensitive = true
}
