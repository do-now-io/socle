# The Kapsule cluster and its pools — docs/scaleway/kapsule-capabilities.md.

resource "scaleway_k8s_cluster" "socle" {
  name        = var.cluster_name
  description = "Socle foundations cluster for ${var.owner} (${var.environment})."
  project_id  = var.project_id
  region      = var.region
  tags        = local.tags

  type    = local.control_plane_type
  version = var.kubernetes_version

  # Cilium is not a choice here, so it is not a variable. Scaleway operates the
  # CNI as a system add-on beside kube-proxy: the version is theirs, Hubble is
  # not shipped, and the kube-proxy replacement the socle uses elsewhere is not
  # available. Calico would be worse on every count.
  cni = "cilium"

  private_network_id          = scaleway_vpc_private_network.socle.id
  delete_additional_resources = var.delete_additional_resources

  # Auto-upgrade covers patches inside the current minor, never the minor
  # itself. Scaleway has no release channel, so moving a minor is a deliberate
  # act by the pipeline, and the window here is what orders the rings: dev
  # early in the week, production last.
  auto_upgrade {
    enable                        = true
    maintenance_window_day        = var.maintenance_window.day
    maintenance_window_start_hour = var.maintenance_window.start_hour
  }

  # Pools follow the cluster's version, so a minor upgrade moves the control
  # plane and the nodes in one operation rather than leaving a skew to track.
  upgrade_pools = true

  autoscaler_config {
    # Scaleway's default expander is random, which picks the pool to grow by
    # coin flip once there is more than one — and there always is, because
    # multi-AZ means one pool per zone.
    expander  = var.autoscaler_expander
    estimator = "binpacking"

    disable_scale_down               = false
    scale_down_unneeded_time         = var.scale_down_unneeded_time
    scale_down_utilization_threshold = var.scale_down_utilization_threshold

    # DaemonSets run on every node by definition, so counting them towards
    # utilisation would keep nearly every node above the scale-down threshold.
    ignore_daemonsets_utilization = true

    # Pools differ by zone, not by shape, so the autoscaler should keep them
    # level rather than letting one zone absorb every scale-up.
    balance_similar_node_groups = true

    # A node holding a Pod with local storage cannot be drained without losing
    # that data. The autoscaler leaves it alone.
    skip_nodes_with_local_storage = true
  }

  lifecycle {
    precondition {
      condition     = var.environment != "prod" || local.control_plane_type != "kapsule"
      error_message = "A production cluster must not run on the mutualized control plane: no SLA, no audit logs, and a 55 MB etcd ceiling."
    }
  }
}

# Kapsule creates every cluster with a default ACL allowing 0.0.0.0/0.
# Declaring this resource replaces that rule; deleting it puts the open rule
# back. The control plane cannot be made private, so this is the boundary.
resource "scaleway_k8s_acl" "socle" {
  cluster_id = scaleway_k8s_cluster.socle.id
  region     = var.region

  dynamic "acl_rules" {
    for_each = var.cluster_endpoint_public_access_cidrs

    content {
      ip          = acl_rules.value
      description = "Allowed by the socle foundations module"
    }
  }
}

# One placement group per zone. Multi-AZ spreads pools across zones, but inside
# a zone nothing otherwise stops a pool's nodes landing on one hypervisor.
resource "scaleway_instance_placement_group" "socle" {
  for_each = local.gateway_zones

  name       = "${var.cluster_name}-${each.value}"
  project_id = var.project_id
  zone       = each.value
  tags       = local.tags

  # Spread the pool's nodes across distinct hypervisors. The mode stays at its
  # default, which is advisory: spreading is worth having, but refusing to
  # scale during a capacity crunch is not. policy_mode is deprecated and goes
  # away with v1 of the Instance API, so it is not set here.
  policy_type = "max_availability"
}

# One pool per zone, because a pool is single-zone and single-typed. There is
# no Karpenter for Scaleway: the shape of these pools is a design decision, not
# something a controller derives from pending Pods.
resource "scaleway_k8s_pool" "socle" {
  for_each = local.gateway_zones

  cluster_id = scaleway_k8s_cluster.socle.id
  name       = "${var.cluster_name}-${each.value}"
  zone       = each.value
  region     = var.region
  node_type  = var.node_type
  tags       = local.tags

  # size is only read at creation once autoscaling is on; min_size and max_size
  # are what govern afterwards.
  size        = var.pool_min_size
  min_size    = var.pool_min_size
  max_size    = var.pool_max_size
  autoscaling = true
  autohealing = true

  container_runtime      = "containerd"
  root_volume_size_in_gb = var.root_volume_size_in_gb

  # Full isolation: no public address on any node. Egress leaves through the
  # Public Gateways, which is what gives the estate a stable source address.
  public_ip_disabled = true

  placement_group_id = scaleway_instance_placement_group.socle[each.value].id
  security_group_id  = scaleway_instance_security_group.socle[each.value].id

  # Without the gateway network in place first, a node with no public address
  # cannot reach its control plane and the pool never converges.
  depends_on = [scaleway_vpc_gateway_network.socle]
}
