# Socle foundations for AWS (EKS).
# Placeholder root module — the real foundations (VPC, EKS cluster,
# identities, Flux bootstrap) will land here.

terraform {
  required_version = ">= 1.8"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

output "hello" {
  description = "Placeholder output proving the module wiring works."
  value       = "Hello from the Socle AWS (EKS) foundations module!"
}