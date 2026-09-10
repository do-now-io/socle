# Socle foundations for AWS.
#
# One flat root module: VPC, EKS cluster and identities. It provisions an
# empty-shell EKS Standard cluster and the identities the Flux-pulled socle
# needs, then steps away. Everything above that — the catalog, the
# observability stack, application infrastructure — arrives through the
# socle OCI artifact and Crossplane.
#
# Every default here traces back to a research document under docs/aws/.
# Resources live in network.tf, cluster.tf and iam.tf.

# The region comes from the provider, never from a variable of our own. A
# variable would be a second source of truth the module cannot enforce
# against the provider's, and the only thing this module needs it for is
# building VPC endpoint service names — which have to match the region the
# resources are actually created in, by construction.
data "aws_region" "current" {}

locals {
  # Stamped onto every billable resource so cost can be attributed and
  # orphans can be found. Bumped with the module's own tag.
  socle_version = "0.1.0-dev"

  # The standard tag set. AWS tags take any UTF-8, so no normalisation is
  # needed here.
  tags = merge(
    {
      owner           = var.owner
      environment     = var.environment
      "socle-version" = local.socle_version
    },
    var.additional_tags,
  )

  # The VPC is referenced by ID rather than looked up through a data
  # source: it keeps the module free of a lookup that would fail on a VPC
  # the consumer manages elsewhere, and it is what the EKS API accepts.
  vpc_id = var.create_vpc ? aws_vpc.socle[0].id : var.vpc_id

  az_count = length(var.availability_zones)

  # Carve vpc_cidr into 2 * az_count equal blocks — one public, one private
  # subnet per AZ — regardless of the prefix length vpc_cidr happens to
  # have. Not a research decision, just arithmetic: ceil(log2(...)) can
  # round up on floating-point edge cases, which only means slightly
  # smaller subnets than the minimum, never a collision.
  subnet_newbits = ceil(log(local.az_count * 2, 2))

  private_subnet_cidrs = var.create_vpc ? [
    for i in range(local.az_count) : cidrsubnet(var.vpc_cidr, local.subnet_newbits, i)
  ] : []

  public_subnet_cidrs = var.create_vpc ? [
    for i in range(local.az_count) : cidrsubnet(var.vpc_cidr, local.subnet_newbits, local.az_count + i)
  ] : []

  private_subnet_ids = var.create_vpc ? aws_subnet.private[*].id : var.private_subnet_ids
  public_subnet_ids  = var.create_vpc ? aws_subnet.public[*].id : var.public_subnet_ids
}
