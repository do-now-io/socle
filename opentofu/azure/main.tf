# Socle foundations for Azure (AKS).
# Placeholder root module — the real foundations (VNet, AKS cluster,
# workload identities, Flux bootstrap) will land here.

terraform {
  required_version = ">= 1.8"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
    }
  }
}

output "hello" {
  description = "Placeholder output proving the module wiring works."
  value       = "Hello from the Socle Azure (AKS) foundations module!"
}
