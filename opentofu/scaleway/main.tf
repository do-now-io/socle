# Socle foundations for Scaleway.
#
# One flat root module: VPC, Private Network, Public Gateways, the Kapsule
# cluster, its node pools and the identities that go with it. It provisions an
# empty-shell cluster, then steps away. Everything above that — the catalog,
# the observability stack, application infrastructure — arrives through the
# socle OCI artifact and Crossplane.
#
# Every default here traces back to a research document under docs/scaleway/.
# Resources live in network.tf, cluster.tf, iam.tf and observability.tf.

locals {
  # Stamped onto every resource that takes tags, so cost can be attributed and
  # orphans can be found. Bumped with the module's own tag.
  socle_version = "0.1.0-dev"

  # Scaleway tags are a flat list of strings, not a map, so the standard set is
  # rendered as key=value. The version is normalised the way it is on the other
  # clouds, to keep one shape of value across the estate.
  tags = concat(
    [
      "owner=${var.owner}",
      "environment=${var.environment}",
      "socle-version=${replace(local.socle_version, ".", "-")}",
      "cluster=${var.cluster_name}",
    ],
    [for k, v in var.additional_tags : "${k}=${v}"],
  )

  vpc_id = var.create_vpc ? scaleway_vpc.socle[0].id : var.vpc_id

  # Production gets a dedicated control plane and everything else does not:
  # the mutualized offer is free but carries no SLA, no audit log and a 55 MB
  # etcd ceiling — docs/scaleway/kapsule-capabilities.md. The derivation is the
  # recommended position; control_plane_type overrides it.
  control_plane_type = coalesce(
    var.control_plane_type,
    var.environment == "prod" ? "kapsule-dedicated-4" : "kapsule",
  )

  # One Public Gateway per zone the pools actually span. The gateway is a
  # zoned resource with no HA of its own, so a single one turns a zone outage
  # into a cluster-wide egress outage — docs/scaleway/kapsule-capabilities.md.
  gateway_zones = toset(var.availability_zones)

  # The egress addresses of those gateways. Under full isolation this is the
  # only source address a node can present, which is what makes an IP-bound
  # IAM condition possible at all — docs/scaleway/managed-scope.md.
  gateway_egress_cidrs = [
    for z in var.availability_zones :
    "${scaleway_vpc_public_gateway_ip.socle[z].address}/32"
  ]
}
