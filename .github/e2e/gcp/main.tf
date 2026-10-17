# CI fixture for gcp, the twin of ../aws/main.tf: a cluster and the bootstrap
# module, nothing else, applied on floci-gcp's real k3s by every job of
# .github/workflows/e2e.yaml for this cloud — the root job included.
#
# Why the root job applies this and not opentofu/clusters/gcp (there is no
# floci.tfvars beside this file, which is how e2e.yaml tells): the gcp root's
# helm provider reaches the cluster's DNS endpoint with gke-gcloud-auth-plugin
# and the system trust store (opentofu/gcp/outputs.tf, helm_kubernetes),
# because that endpoint serves a Google Trust Services certificate. floci-gcp
# advertises its k3s API as localhost:<port> behind k3s's own CA and has no
# DNS endpoint, and it emulates no Cloud Router, NAT or Certificate Manager.
# The foundations are proven by `tofu test` and integration.yaml's apply
# against floci-gcp; their real cluster by the sandbox (#61, M4).
#
# What floci-gcp gives (docs/services/gke.md upstream, measured on 0.11.0):
# CreateCluster starts a k3s container through the Docker socket, the
# endpoint is host:port on the runner, and k3s forwards any bearer token it
# does not know to floci-gcp's webhook, which maps it to cluster-admin — so
# the helm provider and Chainsaw carry a fixed token, with no 60-second
# expiry to work around as on floci's EKS. k3s ships a metrics-server, which
# stands in for GKE's own: the socle installs none on gcp.
terraform {
  required_version = ">= 1.13"
  required_providers {
    google = { source = "hashicorp/google", version = ">= 7.0, < 8.0" }
    helm   = { source = "hashicorp/helm", version = ">= 3.0, < 4.0" }
    # The bootstrap module declares it for its EKS add-ons, count = 0 here.
    aws = { source = "hashicorp/aws", version = ">= 6.0, < 7.0" }
  }
}
variable "socle_version" { type = string }
variable "cosign_identity" {
  type = object({ issuer = string, subject = string })
}
variable "kube" {
  type    = any
  default = {}
}
# Where the bootstrap module comes from: this checkout, for every job but
# the upgrade, which inits from the candidate's published module package —
# oci://ghcr.io/do-now-io/socle/opentofu-modules//opentofu/bootstrap?tag=<tag>
# — as a client's root does. A variable in a module source is evaluated at
# init (OpenTofu 1.8+), so -var on `tofu init` picks it.
variable "bootstrap_source" {
  type    = string
  default = "../../../opentofu/bootstrap"
}
variable "artifact_pull_secret" {
  type    = string
  default = ""
}
# Host mode, not a path prefix: the provider strips the last path segment of
# a custom endpoint, so `<endpoint>/container/` would resolve to the bare
# endpoint (floci-gcp's docs/services/gke.md). container.localhost resolves
# to the loopback through systemd-resolved on the runner, and on macOS.
provider "google" {
  project                   = local.project.id
  region                    = local.region
  access_token              = "floci-gcp"
  user_project_override     = false
  container_custom_endpoint = "http://container.localhost:4588/"
}
# As in opentofu/clusters/gcp: every resource of the aws provider is at
# count = 0 on gcp, and this stub keeps it from looking for credentials.
provider "aws" {
  region                      = "us-east-1"
  access_key                  = "unused"
  secret_key                  = "unused"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
}
locals {
  region = "europe-west1"
  # floci-gcp validates neither: any project id, any number. The number is
  # the one opentofu/gcp/tests/emulator uses.
  project = { id = "socle-e2e", number = "101816500482" }
}
# A test double for floci-gcp's emulated GKE, never a real cluster: the
# endpoint is localhost inside a CI runner, floci-gcp enforces none of these
# attributes, and the hardening lives in the foundations module (opentofu/gcp).
#trivy:ignore:AVD-GCP-0049
#trivy:ignore:AVD-GCP-0050
#trivy:ignore:AVD-GCP-0051
#trivy:ignore:AVD-GCP-0056
#trivy:ignore:AVD-GCP-0059
#trivy:ignore:AVD-GCP-0061
resource "google_container_cluster" "e2e" {
  name                = "socle-e2e-catalog"
  location            = local.region
  initial_node_count  = 1
  deletion_protection = false
}
provider "helm" {
  kubernetes = {
    host                   = "https://${google_container_cluster.e2e.endpoint}"
    cluster_ca_certificate = base64decode(google_container_cluster.e2e.master_auth[0].cluster_ca_certificate)
    token                  = "floci-gcp"
  }
}
module "socle" {
  source       = var.bootstrap_source
  cloud        = "gcp"
  cluster_name = "socle-e2e-catalog"
  environment  = "dev"
  owner        = "platform"
  region       = local.region
  project      = local.project
  # The job's kube over the e2e's one fixed value, as on aws: ArgoCD's redis
  # from Docker Hub, since ECR Public answers the runners' shared egress IPs
  # with 429 (../aws/main.tf says how it was measured). On gcp the
  # monitoring module ships no node-exporter (oci/clusters/gcp/monitoring),
  # so aws's mountPropagation override has nothing to apply to.
  kube = merge({
    argocd = { values = { redis = { image = { repository = "docker.io/library/redis" } } } }
  }, var.kube)
  socle_version        = var.socle_version
  cosign_identity      = var.cosign_identity
  artifact_pull_secret = var.artifact_pull_secret
  # Autopilot provisions nodes as pods ask for them, and the root says so;
  # floci-gcp's one k3s node is there from the start either way.
  schedulable_nodes = null
}
# What the e2e-cluster action writes the kubeconfig from: floci-gcp has no
# get-credentials of its own beyond gcloud's, which the runner would have to
# install for two values.
output "endpoint" {
  description = "The k3s API server, as floci-gcp advertises it (host:port)."
  value       = google_container_cluster.e2e.endpoint
}
output "cluster_ca_certificate" {
  description = "k3s's CA, base64, as GKE returns a cluster's."
  value       = google_container_cluster.e2e.master_auth[0].cluster_ca_certificate
  sensitive   = true
}
