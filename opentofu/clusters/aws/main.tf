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
  crossplane                           = var.aws.crossplane
}

# The one value the root derives for the crossplane module: when the
# foundations mint Crossplane's identity (aws.crossplane), the boundary every
# role it creates must carry is what kube.crossplane.permissions_boundary
# takes, so the client does not copy an ARN from one output into another
# input. A value the client wrote wins. Both branches are maps of strings so
# the conditional type-checks, and the try() hands a kube that is not an
# object to the bootstrap module untouched, for its validations to refuse
# with their own message.
locals {
  crossplane_boundary = var.aws.crossplane == null ? tomap({}) : tomap({ permissions_boundary = module.foundations.crossplane_permissions_boundary_arn })
  kube = try(
    merge(var.kube, { crossplane = merge(local.crossplane_boundary, try(var.kube.crossplane, {})) }),
    var.kube,
  )
}

# A warning, not an error: Crossplane without its identity still installs and
# converges, but every CloudAccess it is given fails at the AWS API.
check "crossplane_has_an_identity" {
  assert {
    condition     = !try(var.kube.crossplane.enabled, false) || var.aws.crossplane != null
    error_message = "kube.crossplane.enabled is set without aws.crossplane: the AWS provider runs with no identity, and every CloudAccess will fail. Set aws.crossplane, or keep Crossplane off."
  }
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
  region       = var.aws.region

  kube                 = local.kube
  socle_version        = var.socle_version
  cosign_identity      = var.cosign_identity
  artifact_url         = var.artifact_url
  artifact_pull_secret = var.artifact_pull_secret

  # Cilium, and CoreDNS with it, before Flux: EKS is created with no CNI.
  # What Cilium needs to know comes from the foundations, not from the tfvars.
  cilium  = var.cilium
  coredns = var.coredns
  cluster_network = {
    api_endpoint = module.foundations.cluster_endpoint
    service_cidr = module.foundations.service_cidr
  }

  depends_on = [module.foundations]
}
