output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.foundations.cluster_name
}

output "cluster_endpoint" {
  description = "The control plane's API endpoint."
  value       = module.foundations.cluster_endpoint
}

output "artifact" {
  description = "The socle artifact this cluster pulls, as URL and tag."
  value       = module.socle.artifact
}

output "inputs" {
  description = "What the catalog renders from, after normalisation. Compare with kubectl -n flux-system get resourcesetinputprovider socle -o yaml."
  value       = module.socle.inputs
}
