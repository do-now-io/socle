# Integration fixture: plans the module against the emulator, so that CI
# exercises the whole resource graph without a cloud account or a secret.
#
# It exists because the module itself has no default for the nine variables a
# consumer must decide on, which is deliberate: a root module with values
# baked in would be a second, silent set of recommendations. The fixture is
# where CI's throwaway values live instead.
#
# The leg stops at the plan, and that is an emulator limit, not a module one.
# Measured against the image the workflow pins: 37 of the module's 39 resources
# apply and destroy cleanly — the VPC and everything in it, the cluster, both
# log groups, the flow log, the KMS keys and the roles. Two do not:
#
# both resources that blocked it have since left the module — the managed
# policy attachment with the EBS CSI role, and the Pod Identity association
# with Crossplane's. Re-measure before trusting this leg's status either way:
# what it can and cannot do has changed twice already.

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
