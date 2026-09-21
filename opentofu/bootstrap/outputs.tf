output "namespace" {
  description = "Namespace holding the operator and the Flux controllers."
  value       = helm_release.operator.namespace
}

output "operator_version" {
  description = "Version of flux-operator installed, which is also the chart version."
  value       = helm_release.operator.version
}

output "flux_version" {
  description = "Flux version the operator converges the controllers to."
  value       = var.flux_version
}

output "sync_name" {
  description = "Name of the root source and Kustomization the operator creates. Immutable in the CRD."
  value       = local.sync_name
}

output "sync_source" {
  description = "What this cluster pulls, as kind, URL and pinned reference."
  value = {
    kind = var.sync_kind
    url  = var.sync_url
    ref  = var.sync_ref
    path = var.sync_path
  }
}

output "cosign_verification" {
  description = "Whether the root artifact's signature is verified, and against which identity. False means an unsigned or foreign artifact would be applied."
  value = {
    enabled  = var.cosign_verification_enabled
    identity = var.cosign_identity
  }
}
