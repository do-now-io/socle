# The socle on AWS, in one apply: the cluster, then Flux and the catalog on it.
#
# In the repository the two sources are relative, so this root is what CI
# applies. A client's copy points both at the published module, with the
# version in the source:
#
#   source = "oci://ghcr.io/do-now-io/socle/opentofu-modules//opentofu/aws?tag=${var.socle_version}"
#   source = "oci://ghcr.io/do-now-io/socle/opentofu-modules//opentofu/bootstrap?tag=${var.socle_version}"
#
# (the modules package, not the socle artifact: one OCI tag cannot carry both
# shapes — PR #15)
#
# Two cases need more than one apply, both documented in README.md: replacing
# the cluster, and destroying it when the runner cannot reach the API.

provider "aws" {
  region = var.aws.region
}

module "foundations" {
  source = "../../aws"

  cluster_name    = var.aws.cluster_name
  owner           = var.aws.owner
  environment     = var.aws.environment
  additional_tags = var.aws.additional_tags

  create_vpc         = var.aws.create_vpc
  vpc_id             = var.aws.vpc_id
  private_subnet_ids = var.aws.private_subnet_ids
  public_subnet_ids  = var.aws.public_subnet_ids
  vpc_cidr           = var.aws.vpc_cidr
  availability_zones = var.aws.availability_zones
  create_nat_gateway = var.aws.create_nat_gateway

  vpc_flow_logs_enabled                = var.aws.vpc_flow_logs_enabled
  cluster_endpoint_public_access_cidrs = var.aws.cluster_endpoint_public_access_cidrs
  secrets_encryption_enabled           = var.aws.secrets_encryption_enabled
  secrets_encryption_kms_key_arn       = var.aws.secrets_encryption_kms_key_arn
  cluster_log_types                    = var.aws.cluster_log_types
  log_retention_days                   = var.aws.log_retention_days
  kubernetes_version                   = var.aws.kubernetes_version
  force_update_version                 = var.aws.force_update_version
}

# One line, identical on every cloud. No credential: the exec plugin inside
# obtains a token at call time from the same ambient credentials as the aws
# provider above.
provider "helm" {
  kubernetes = module.foundations.helm_kubernetes
}

module "socle" {
  source = "../../bootstrap"

  cloud        = "aws"
  cluster_name = var.aws.cluster_name
  environment  = var.aws.environment
  owner        = var.aws.owner

  kube                 = var.kube
  socle_version        = var.socle_version
  cosign_identity      = var.cosign_identity
  artifact_url         = var.artifact_url
  artifact_pull_secret = var.artifact_pull_secret

  depends_on = [module.foundations]
}
