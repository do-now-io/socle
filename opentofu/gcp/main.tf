# Socle foundations for Google Cloud (GKE).
# Placeholder root module — the real foundations (VPC, GKE cluster,
# Workload Identity, Flux bootstrap) will land here.

terraform {
  required_version = ">= 1.8"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0"
    }
  }
}

output "hello" {
  description = "Placeholder output proving the module wiring works."
  value       = "Hello from the Socle Google Cloud (GKE) foundations module!"
}
