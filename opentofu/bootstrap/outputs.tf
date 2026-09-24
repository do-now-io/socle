output "inputs" {
  description = "What this module ships into the cluster as the ResourceSetInputProvider's defaultValues, after normalisation against the catalog. The catalog's templates read exactly these paths."
  value       = local.inputs
}

output "socle_version" {
  description = "Tag of the socle artifact the cluster pulls."
  value       = local.version
}

output "artifact" {
  description = "The socle artifact, as OCI URL and tag."
  value = {
    url = var.artifact_url
    tag = local.version
  }
}

output "cosign_identity" {
  description = "Keyless identity the artifact's signature is verified against, on every reconciliation."
  value       = var.cosign_identity
}

output "namespace" {
  description = "Namespace holding the operator, the Flux controllers and the socle's inputs."
  value       = local.namespace
}

output "operator_version" {
  description = "Version of flux-operator installed, which is also its chart version."
  value       = var.operator_version
}

output "flux_version" {
  description = "Flux version the operator converges the controllers to."
  value       = var.flux_version
}
