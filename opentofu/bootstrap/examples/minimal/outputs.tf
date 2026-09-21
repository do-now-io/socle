output "namespace" {
  description = "Namespace holding the operator and the Flux controllers."
  value       = module.bootstrap.namespace
}

output "sync_source" {
  description = "What this cluster pulls, and at which pinned reference."
  value       = module.bootstrap.sync_source
}

output "cosign_verification" {
  description = "Whether the artifact's signature is verified, and against which identity."
  value       = module.bootstrap.cosign_verification
}
