output "cluster_name" {
  value = module.socle.cluster_name
}

output "cluster_endpoint" {
  value = module.socle.cluster_endpoint
}

output "cluster_ca_certificate" {
  value     = module.socle.cluster_ca_certificate
  sensitive = true
}

output "oidc_issuer_url" {
  value = module.socle.oidc_issuer_url
}
