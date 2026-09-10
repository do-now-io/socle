# The smallest deployable socle foundation on AWS: a region, a name, who
# owns it, the AZs to spread across, and the handful of variables the
# module deliberately leaves with no default. Everything else is the
# module's recommended position.
#
# Remote state deliberately lives in the consumer's own account and is not
# configured here — see README.md.

provider "aws" {
  region = var.region
}

module "socle" {
  source = "../../"

  # No region here: the module takes it from the provider above.
  cluster_name = var.cluster_name
  owner        = var.owner
  environment  = var.environment

  availability_zones = var.availability_zones

  # Greenfield: let the module build the VPC. Point vpc_id at an existing
  # one instead when the consumer already owns one.
  create_vpc = true

  kubernetes_version = var.kubernetes_version

  # No good default exists for who may reach the public API endpoint, so
  # the module has none — replace with the consumer's own admin CIDR.
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  # Pinned by whoever triggers the bump, never most_recent — check current
  # versions with `aws eks describe-addon-versions` before a real apply.
  coredns_addon_version            = var.coredns_addon_version
  ebs_csi_addon_version            = var.ebs_csi_addon_version
  pod_identity_agent_addon_version = var.pod_identity_agent_addon_version
}
