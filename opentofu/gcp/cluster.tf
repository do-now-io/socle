# The cluster — docs/gcp/cluster-mode.md (Autopilot only) and
# docs/gcp/managed-scope.md (channel, maintenance, add-ons, identity).
#
# Autopilot is not a variable. A cluster mode is fixed at creation, supporting
# both would double the surface this module has to cover, and every hardening
# default the socle relies on — Workload Identity Federation, Dataplane V2,
# Shielded nodes, network policy — is enforced rather than requested.

# Three scanner findings are answered here rather than argued in a review.
#
# Master authorized networks (GCP-0061) govern the IP endpoints this cluster
# does not expose: control_plane_endpoints_config disables them, and the
# boundary is IAM plus VPC Service Controls.
#
# Network policy (GCP-0056) is always on under Dataplane V2, which Autopilot
# enforces; the network_policy block is rejected outright on an Autopilot
# cluster.
#
# A node service account (GCP-0050) cannot be set on Autopilot at all —
# Google owns the nodes. There is no node_config to put one in.
#
# All three are argued in docs/gcp/network-security.md and docs/gcp/cluster-mode.md.
#trivy:ignore:AVD-GCP-0061
#trivy:ignore:AVD-GCP-0056
#trivy:ignore:AVD-GCP-0050
resource "google_container_cluster" "socle" {
  project  = var.project_id
  name     = var.cluster_name
  location = var.region

  enable_autopilot    = true
  deletion_protection = var.deletion_protection
  description         = "Socle foundations cluster (${var.environment})"

  network    = local.network_path
  subnetwork = local.subnetwork_path

  # Raise-only floor. Null in steady state: the release channel decides.
  min_master_version = var.kubernetes_min_version

  release_channel {
    channel = var.release_channel
  }

  # VPC-native, with no Services range: GKE assigns Service addresses from its
  # own managed range, so there is nothing to size or to collide with.
  ip_allocation_policy {
    cluster_secondary_range_name = local.pod_range_name
  }

  private_cluster_config {
    enable_private_nodes = var.enable_private_nodes
  }

  # The DNS-based endpoint is the access path: a stable FQDN, authorised by
  # IAM, reachable wherever Google Cloud APIs are. IP endpoints are off, and
  # with them the authorized-networks maintenance problem.
  control_plane_endpoints_config {
    dns_endpoint_config {
      allow_external_traffic = var.control_plane_dns_allow_external_traffic
    }

    ip_endpoints_config {
      enabled = var.control_plane_ip_endpoints_enabled
    }
  }

  # No client certificate: it is a long-lived credential nothing in the socle
  # uses.
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  # Shielded nodes, Dataplane V2 and network policy are enforced by Autopilot
  # and conflict with being set explicitly, which is why no variable and no
  # attribute for them appears here.

  # Who gets upgraded when. The window is required, and its day of the week is
  # what orders a dev/staging/prod ring inside one release channel.
  maintenance_policy {
    recurring_window {
      start_time = var.maintenance_window.start_time
      end_time   = var.maintenance_window.end_time
      recurrence = var.maintenance_window.recurrence
    }

    dynamic "maintenance_exclusion" {
      for_each = { for e in var.maintenance_exclusions : e.name => e }

      content {
        exclusion_name = maintenance_exclusion.value.name
        start_time     = maintenance_exclusion.value.start_time
        end_time       = maintenance_exclusion.value.end_time

        exclusion_options {
          scope = maintenance_exclusion.value.scope
        }
      }
    }
  }

  logging_config {
    enable_components = var.logging_components
  }

  # Managed collection is the ingestion path and carries no fee of its own;
  # what it ingests is billed per sample, which is why the component list
  # defaults to the free one. Auto-monitoring is deliberately not configured.
  monitoring_config {
    enable_components = var.monitoring_components

    managed_prometheus {
      enabled = true
    }
  }

  # Adds cluster, namespace and workload labels to the detailed billing
  # export. On from day one because it does not backfill.
  cost_management_config {
    enabled = var.cost_allocation_enabled
  }

  dynamic "addons_config" {
    for_each = var.backup_agent_enabled ? [1] : []

    content {
      gke_backup_agent_config {
        enabled = true
      }
    }
  }

  dynamic "notification_config" {
    for_each = var.enable_upgrade_notifications ? [1] : []

    content {
      pubsub {
        enabled = true
        topic   = google_pubsub_topic.upgrade_notifications[0].id
      }
    }
  }

  resource_labels = local.labels

  depends_on = [google_compute_subnetwork.socle]
}
