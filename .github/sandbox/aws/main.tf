# The release's proof on real AWS (#61, M4): the client root
# opentofu/clusters/aws, called as a client calls it — from the published
# module package, at the candidate's tag — in the sandbox account. Applied,
# proven and destroyed by .github/workflows/sandbox.yaml, on the release PR
# only. Nothing here is a recommendation: the client's own copy is
# opentofu/clusters/aws/prod.tfvars.example.
terraform {
  required_version = ">= 1.13"
}

# Evaluated at init (OpenTofu 1.8+): the package and the tag the release PR
# just published.
variable "socle_source" {
  description = "The root, from the module package: oci://ghcr.io/<repository>/opentofu-modules//opentofu/clusters/aws?tag=<tag>. The default, this checkout's, is what pr-static validates."
  type        = string
  default     = "../../../opentofu/clusters/aws"
}

variable "socle_version" {
  description = "The candidate's tag, the one in socle_source."
  type        = string
}

variable "cosign_identity" {
  description = "The workflow identity the candidate's artifact is signed as."
  type        = object({ issuer = string, subject = string })
}

variable "api_cidrs" {
  description = "Who may reach the API endpoint: the runner that applies, as /32."
  type        = list(string)
  default     = ["203.0.113.0/32"]
}

module "socle" {
  source = var.socle_source

  socle_version   = var.socle_version
  cosign_identity = var.cosign_identity

  aws = {
    region                               = "eu-west-3"
    cluster_name                         = "socle-sandbox"
    owner                                = "platform"
    environment                          = "sandbox"
    kubernetes_version                   = "1.34"
    availability_zones                   = ["eu-west-3a", "eu-west-3b"]
    cluster_endpoint_public_access_cidrs = var.api_cidrs
    # The account's public zone: the shared Gateways' certificate, and the
    # zone external-dns writes to.
    gateway_certificate = { domain = "sandbox.kubemulus.com" }
    crossplane          = { allowed_services = ["route53"] }
  }

  # The catalog's defaults, and the modules that hold the cloud's identity
  # (Crossplane, and external-dns, derived on by the root from the
  # certificate). What a client gets on day one.
  kube = {
    crossplane = { enabled = true }
  }
}

output "cluster_name" {
  description = "The EKS cluster, for the kubeconfig."
  value       = module.socle.cluster_name
}
