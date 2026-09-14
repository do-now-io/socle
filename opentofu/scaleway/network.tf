# Network — docs/scaleway/kapsule-capabilities.md.
#
# One VPC per environment, one Private Network per cluster, and a Public
# Gateway in every zone the pools span. Nodes carry no public address at all:
# full isolation is the position on every environment, so that dev and staging
# exercise the same egress path production does.

resource "scaleway_vpc" "socle" {
  count = var.create_vpc ? 1 : 0

  name       = "${var.cluster_name}-vpc"
  project_id = var.project_id
  region     = var.region
  tags       = local.tags
}

# Kapsule takes a /22 for the cluster. Creating the Private Network here rather
# than letting Kapsule create one is what makes the range ours to choose, and
# what lets the gateways attach to it before the cluster exists.
resource "scaleway_vpc_private_network" "socle" {
  name       = "${var.cluster_name}-pn"
  vpc_id     = local.vpc_id
  project_id = var.project_id
  region     = var.region
  tags       = local.tags

  ipv4_subnet {
    subnet = var.private_network_cidr
  }
}

# A flexible IP per gateway, reserved explicitly rather than left to the
# gateway to allocate. It is the estate's stable egress address: it goes in an
# IAM policy condition, and it is what a client allow-lists on their side.
resource "scaleway_vpc_public_gateway_ip" "socle" {
  for_each = local.gateway_zones

  project_id = var.project_id
  zone       = each.value
  tags       = local.tags
}

# The Public Gateway is a zoned resource with no high availability of its own.
# Scaleway's own answer to a zone outage is several gateways on one Private
# Network, each advertising a default route, so the module builds one per zone
# the pools span rather than one per cluster.
resource "scaleway_vpc_public_gateway" "socle" {
  for_each = local.gateway_zones

  name       = "${var.cluster_name}-gw-${each.value}"
  type       = var.public_gateway_type
  project_id = var.project_id
  zone       = each.value
  ip_id      = scaleway_vpc_public_gateway_ip.socle[each.value].id
  tags       = local.tags

  # SSH bastion stays off. Node access for debugging goes through the
  # Kubernetes API, and a bastion on the egress path is an inbound surface the
  # allow-list does not cover.
  bastion_enabled = false
}

# One IPAM reservation per gateway, so each gateway holds a fixed address on
# the Private Network rather than a lease that moves.
resource "scaleway_ipam_ip" "gateway" {
  for_each = local.gateway_zones

  project_id = var.project_id
  region     = var.region
  tags       = local.tags

  source {
    private_network_id = scaleway_vpc_private_network.socle.id
  }
}

# Attaching a gateway advertises a default route onto the Private Network and
# turns on dynamic NAT. Every gateway advertises: with a recent node kernel the
# traffic spreads across them, and losing one zone costs that zone's share
# rather than the cluster's egress.
#
# This is also the cluster's lifeline. Fully isolated nodes reach their control
# plane through here, so detaching every gateway takes the cluster down.
resource "scaleway_vpc_gateway_network" "socle" {
  for_each = local.gateway_zones

  gateway_id         = scaleway_vpc_public_gateway.socle[each.value].id
  private_network_id = scaleway_vpc_private_network.socle.id
  zone               = each.value
  enable_masquerade  = true

  ipam_config {
    push_default_route = true
    ipam_ip_id         = scaleway_ipam_ip.gateway[each.value].id
  }
}

# Kapsule otherwise attaches new clusters to a "Kapsule default security group"
# that is shared between clusters in the Project: opening a port for one opens
# it for all of them. The module gives each cluster its own.
#
# Inbound is dropped outright. Nodes have no public interface under full
# isolation, and everything that reaches a workload arrives through a Load
# Balancer the cloud controller manager creates.
# One per zone, because an Instance security group is a zoned resource and a
# pool can only reference one from its own zone.
resource "scaleway_instance_security_group" "socle" {
  for_each = local.gateway_zones

  name                    = "${var.cluster_name}-nodes-${each.value}"
  description             = "Socle node security group for ${var.cluster_name} in ${each.value}. Owned by the foundations module; not the shared Kapsule default."
  project_id              = var.project_id
  zone                    = each.value
  stateful                = true
  inbound_default_policy  = "drop"
  outbound_default_policy = "accept"
  tags                    = local.tags
}
