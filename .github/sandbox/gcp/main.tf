# The release's proof on real Google Cloud (#61, M4): the client root
# opentofu/clusters/gcp, called as a client calls it — from the published
# module package, at the candidate's tag — in the sandbox project. Applied,
# proven and destroyed by .github/workflows/sandbox.yaml, on the release PR
# only. Nothing here is a recommendation: the client's own copy is
# opentofu/clusters/gcp/prod.tfvars.example.
terraform {
  required_version = ">= 1.13"
}

variable "socle_source" {
  description = "The root, from the module package: oci://ghcr.io/<repository>/opentofu-modules//opentofu/clusters/gcp?tag=<tag>. The default, this checkout's, is what pr-static validates."
  type        = string
  default     = "../../../opentofu/clusters/gcp"
}

variable "socle_version" {
  description = "The candidate's tag, the one in socle_source."
  type        = string
}

variable "cosign_identity" {
  description = "The workflow identity the candidate's artifact is signed as."
  type        = object({ issuer = string, subject = string })
}

module "socle" {
  source = var.socle_source

  socle_version   = var.socle_version
  cosign_identity = var.cosign_identity

  gcp = {
    project_id     = "sandbox-2bace"
    project_number = "320449067541"
    region         = "europe-west1"
    cluster_name   = "socle-sandbox"
    owner          = "platform"
    environment    = "sandbox"
    create_network = true
    maintenance_window = {
      start_time = "2026-01-03T02:00:00Z"
      end_time   = "2026-01-03T14:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SA"
    }
    # The sandbox's own run must not be held by a protection a destroy
    # would have to lift first.
    deletion_protection = false
    crossplane          = {}
    gateway_certificate = { dns_zone = "sandbox-gcp-do-now-io", domains = ["sandbox-gcp.do-now.io"] }
  }

  # The catalog's defaults minus ArgoCD and the monitoring stack: a fresh
  # project's quotas (two Autopilot nodes, 250 GB of SSD in the region) do
  # not hold the whole catalog at once (docs/clouds/gcp/sizing.md). Crossplane
  # on, so external-dns is derived on from the certificate.
  kube = {
    crossplane = { enabled = true }
    argocd     = { enabled = false }
    monitoring = { enabled = false }
  }
}

output "cluster_name" {
  description = "The GKE cluster, for the kubeconfig."
  value       = module.socle.cluster_name
}
