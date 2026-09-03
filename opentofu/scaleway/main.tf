# Socle foundations for Scaleway (Kapsule).
# Placeholder root module — the real foundations (VPC, Kapsule cluster,
# IAM application, Flux bootstrap) will land here.

terraform {
  required_version = ">= 1.8"

  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = ">= 2.0"
    }
  }
}

output "hello" {
  description = "Placeholder output proving the module wiring works."
  value       = "Hello from the Socle Scaleway (Kapsule) foundations module!"
}
