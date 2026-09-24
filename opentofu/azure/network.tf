# Network — docs/azure/network-security.md.
#
# One VNet, one node-only subnet. Azure subnets aren't AZ-scoped at all —
# zone placement happens on the node pool itself (see cluster.tf), not on
# the subnet — and there is no public subnet to carve out: the Standard
# Load Balancer a Kubernetes Service of type LoadBalancer provisions
# attaches a public IP directly to its own frontend, backed by the node
# subnet's private IPs. Nothing here needs to sit in a publicly routable
# subnet.
#
# The subnet is sized for nodes only, never pods: Cilium — installed by the
# bootstrap module before Flux, not by this module — owns pod IPAM entirely,
# from var.pod_cidr, once it replaces the BYO CNI placeholder cluster.tf
# leaves nodes with at creation.

resource "azurerm_resource_group" "socle" {
  count = var.create_resource_group ? 1 : 0

  name     = var.resource_group_name
  location = var.location

  tags = local.tags
}

resource "azurerm_virtual_network" "socle" {
  count = var.create_vnet ? 1 : 0

  name                = "${var.cluster_name}-vnet"
  address_space       = [var.vnet_cidr]
  resource_group_name = local.resource_group_name
  location            = local.location

  tags = local.tags
}

locals {
  vnet_name      = var.create_vnet ? azurerm_virtual_network.socle[0].name : var.vnet_name
  node_subnet_id = var.create_vnet ? azurerm_subnet.node[0].id : var.node_subnet_id
}

# One subnet, covering the whole VNet — there is nothing else in this VNet
# to carve address space out for. A client who needs more subnets (private
# endpoints, a hub-and-spoke peer) attaches their own VNet instead
# (create_vnet = false) rather than this module growing a second subnet
# nobody asked for.
resource "azurerm_subnet" "node" {
  count = var.create_vnet ? 1 : 0

  name                 = "${var.cluster_name}-nodes"
  resource_group_name  = local.resource_group_name
  virtual_network_name = local.vnet_name
  address_prefixes     = [var.vnet_cidr]
}

# One NAT Gateway per VNet — not per AZ. An Azure NAT Gateway is a
# zonal-or-regional resource attached directly to a subnet that already
# spans every zone — there is no per-AZ duplication to avoid or pay for.
resource "azurerm_public_ip" "nat" {
  count = var.create_vnet && var.create_nat_gateway ? 1 : 0

  name                = "${var.cluster_name}-nat"
  resource_group_name = local.resource_group_name
  location            = local.location
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = local.tags
}

resource "azurerm_nat_gateway" "socle" {
  count = var.create_vnet && var.create_nat_gateway ? 1 : 0

  name                = "${var.cluster_name}-nat"
  resource_group_name = local.resource_group_name
  location            = local.location
  sku_name            = "Standard"

  tags = local.tags
}

resource "azurerm_nat_gateway_public_ip_association" "socle" {
  count = var.create_vnet && var.create_nat_gateway ? 1 : 0

  nat_gateway_id       = azurerm_nat_gateway.socle[0].id
  public_ip_address_id = azurerm_public_ip.nat[0].id
}

resource "azurerm_subnet_nat_gateway_association" "node" {
  count = var.create_vnet && var.create_nat_gateway ? 1 : 0

  subnet_id      = azurerm_subnet.node[0].id
  nat_gateway_id = azurerm_nat_gateway.socle[0].id
}
