# Integration fixture: plans the module against the emulator, so that CI
# exercises the whole resource graph without a cloud account or a secret.
#
# It exists because the module itself has no default for the nine variables a
# consumer must decide on, which is deliberate: a root module with values
# baked in would be a second, silent set of recommendations. The fixture is
# where CI's throwaway values live instead.
#
# The leg stops at the plan, and that is an emulator limit, not a module one.
# Measured against the image the workflow pins: the first apply succeeds
# clean, all 34 resources — the blockers from an earlier version of this
# module (a managed policy the emulator didn't ship, a Pod Identity
# association API it didn't implement) left with the resources that needed
# them.
#
# What replaces them: a second `plan` — or `destroy`, which plans first —
# against the same cluster fails outright. DescribeCluster on this image
# comes back with an empty `identity`, though CreateCluster populated it at
# apply time, so `oidc_issuer_url` (aws_eks_cluster.socle.identity[0].oidc[0]
# .issuer) errors on a nonexistent index instead of just drifting. The same
# read loses enabled_cluster_log_types, encryption_config and two IAM roles'
# tags, and the flow log's iam_role_arn comes back empty, which forces a
# replace. None of this reproduces on floci/floci:latest-compat, where every
# field survives the read — so it is a gap in this specific image's
# DescribeCluster response, not a module bug. Re-measure before trusting
# this leg's status either way: what it can and cannot do has changed three
# times already.

variable "endpoint" {
  description = "Base URL of the floci emulator."
  type        = string
  default     = "http://localhost:4566"
}

# Credentials are not cryptographically validated by the emulator; the static
# pair exists only so the provider does not go looking for real ones.
provider "aws" {
  region     = "eu-west-1"
  access_key = "test"
  secret_key = "test"

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_region_validation      = true

  # floci answers every service on the same port.
  endpoints {
    ec2  = var.endpoint
    eks  = var.endpoint
    iam  = var.endpoint
    kms  = var.endpoint
    logs = var.endpoint
    sts  = var.endpoint
  }
}

module "socle" {
  source = "../../"

  cluster_name = "socle-emulator"
  owner        = "platform"
  environment  = "dev"

  availability_zones = ["eu-west-1a", "eu-west-1b"]

  kubernetes_version                   = "1.34"
  cluster_endpoint_public_access_cidrs = ["203.0.113.0/32"]
}

output "cluster_name" {
  description = "Proves the cluster came back from the emulator."
  value       = module.socle.cluster_name
}

output "cluster_endpoint" {
  description = "Proves the control plane answered with an endpoint."
  value       = module.socle.cluster_endpoint
}
