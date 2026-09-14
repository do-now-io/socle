# The outputs a socle bootstrap needs. Re-exported so that `tofu output` on
# this example shows the full set the conformance checklist requires — including
# the two that are null on this cloud and null nowhere else.

output "cluster_name" {
  description = "Name of the cluster."
  value       = module.socle.cluster_name
}

output "cluster_endpoint" {
  description = "URL of the Kubernetes API server."
  value       = module.socle.cluster_endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate."
  value       = module.socle.cluster_ca_certificate
  sensitive   = true
}

output "oidc_issuer_url" {
  description = "Null on Scaleway: Kapsule exposes no OIDC issuer for workload identity."
  value       = module.socle.oidc_issuer_url
}

output "workload_identity_pool" {
  description = "Null on Scaleway: there is no workload identity federation."
  value       = module.socle.workload_identity_pool
}

output "crossplane_access_key" {
  description = "Access key of the in-cluster Crossplane identity."
  value       = module.socle.crossplane_access_key
}

output "crossplane_secret_key" {
  description = "Secret key of the in-cluster Crossplane identity."
  value       = module.socle.crossplane_secret_key
  sensitive   = true
}

output "gateway_egress_cidrs" {
  description = "The addresses this cluster's nodes egress from."
  value       = module.socle.gateway_egress_cidrs
}
