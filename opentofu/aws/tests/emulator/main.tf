# Integration fixture: plans the module against the floci emulator, so that CI
# exercises the whole resource graph without a cloud account or a secret.
#
# It exists because the module itself has no default for the nine variables a
# consumer must decide on, which is deliberate: a root module with values
# baked in would be a second, silent set of recommendations. The fixture is
# where CI's throwaway values live instead.
#
# The leg stops at the plan, and that is an emulator limit, not a module one.
# Measured against floci 1.5.34 (community edition):
#
# - EKS CreateAddon is not emulated at all — the request falls through to the
#   S3 handler and comes back as an S3 XML error.
# - Only five AWS-managed policies exist there, and
#   service-role/AmazonEBSCSIDriverPolicy is not among them.
#
# Everything else applies clean: the VPC, subnets, NAT, endpoints, the cluster
# itself, both log groups, the flow log and all three identities. Either an
# upstream fix or a fuller emulator flips this leg back to apply.

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

  coredns_addon_version            = "v1.11.4-eksbuild.10"
  ebs_csi_addon_version            = "v1.44.0-eksbuild.1"
  pod_identity_agent_addon_version = "v1.3.4-eksbuild.1"

  # Exercises the policy-attachment loop, which is empty by default.
  crossplane_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
}

output "cluster_name" {
  description = "Proves the cluster came back from the emulator."
  value       = module.socle.cluster_name
}

output "cluster_endpoint" {
  description = "Proves the control plane answered with an endpoint."
  value       = module.socle.cluster_endpoint
}

output "crossplane_role_arn" {
  description = "Proves the identity the socle needs was created."
  value       = module.socle.crossplane_role_arn
}
