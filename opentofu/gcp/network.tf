# Reference network — docs/gcp/network-security.md.
#
# Custom-mode VPC, one subnetwork per cluster, one secondary range for Pods,
# no Services range (GKE manages its own on Autopilot 1.27 and later), a
# proxy-only subnetwork without which no regional Gateway can exist, and
# Cloud NAT because private nodes cannot pull an image without it.

resource "google_compute_network" "socle" {
  count = var.create_network ? 1 : 0

  project = var.project_id
  name    = var.cluster_name

  # Custom mode: the consumer picks ranges that do not collide with what they
  # already run. Auto mode would claim a subnet in every region.
  auto_create_subnetworks = false
  description             = "Socle foundations network for ${var.cluster_name}"
}

resource "google_compute_subnetwork" "socle" {
  count = var.create_subnetwork ? 1 : 0

  project       = var.project_id
  name          = var.cluster_name
  region        = var.region
  network       = local.network_path
  ip_cidr_range = var.node_range_cidr

  # Private nodes reach Google APIs over this, not over the internet.
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = local.pod_range_name
    ip_cidr_range = var.pod_range_cidr
  }

  # On by default. Vended network logs are billed at $0.25/GiB, and at
  # half sampling over ten-minute windows a socle cluster produces single
  # digits of GiB a month — a dollar or so for the only record of who talked
  # to whom. Turn it off where that record is not wanted.
  dynamic "log_config" {
    for_each = var.subnet_flow_logs_enabled ? [1] : []

    content {
      aggregation_interval = "INTERVAL_10_MIN"
      flow_sampling        = 0.5
      metadata             = "INCLUDE_ALL_METADATA"
    }
  }
}

# Every regional Envoy-based load balancer in a region and VPC shares one pool
# of proxies from this subnetwork, so a second cluster in the same region must
# not try to create it again.
#
# It holds Google's load balancer proxies and nothing of ours, so Private
# Google Access (GCP-0075) has no workload to serve and flow logs (GCP-0076,
# GCP-0029) have no flows of ours to record.
#trivy:ignore:AVD-GCP-0075
#trivy:ignore:AVD-GCP-0076
#trivy:ignore:AVD-GCP-0029
resource "google_compute_subnetwork" "proxy_only" {
  count = var.create_proxy_only_subnet ? 1 : 0

  project       = var.project_id
  name          = "${var.cluster_name}-proxy-only"
  region        = var.region
  network       = local.network_path
  ip_cidr_range = var.proxy_only_range_cidr
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
}

resource "google_compute_router" "socle" {
  count = var.create_nat ? 1 : 0

  project = var.project_id
  name    = var.cluster_name
  region  = var.region
  network = local.network_path
}

resource "google_compute_router_nat" "socle" {
  count = var.create_nat ? 1 : 0

  project = var.project_id
  name    = var.cluster_name
  region  = var.region
  router  = google_compute_router.socle[0].name

  nat_ip_allocate_option = "AUTO_ONLY"

  # Only the cluster subnetwork egresses through this gateway, primary range
  # and Pod range alike. A blanket ALL_SUBNETWORKS would quietly give egress
  # to anything else the consumer later puts in this VPC.
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = local.subnetwork_path
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  # Errors only: NAT logs are Cloud Logging volume, and a dropped-packet log
  # line is the one that matters when ports run out.
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
