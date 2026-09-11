# The outputs a socle bootstrap needs. Re-exported so that `tofu output` on
# this example shows the full set the conformance checklist requires.

output "cluster_name" {
  description = "Name of the cluster."
  value       = module.socle.cluster_name
}

output "cluster_endpoint" {
  description = "The control plane's API endpoint."
  value       = module.socle.cluster_endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate."
  value       = module.socle.cluster_ca_certificate
  sensitive   = true
}

output "oidc_issuer_url" {
  description = "The cluster's OIDC issuer URL."
  value       = module.socle.oidc_issuer_url
}
