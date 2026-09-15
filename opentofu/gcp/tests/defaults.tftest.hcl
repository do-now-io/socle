# A consumer who sets nothing gets the recommended configuration. These runs
# assert that, and that the preconditions guarding incoherent inputs fire.
#
# A static access token keeps the plan offline: nothing here refreshes state
# or reads an existing resource, so no API call is made.

provider "google" {
  project      = "socle-test-project"
  region       = "europe-west1"
  access_token = "offline-fixture-token"
}

variables {
  project_id   = "socle-test-project"
  region       = "europe-west1"
  cluster_name = "socle-test"
  owner        = "platform"
  environment  = "prod"

  create_network = true

  maintenance_window = {
    start_time = "2026-01-03T02:00:00Z"
    end_time   = "2026-01-03T14:00:00Z"
    recurrence = "FREQ=WEEKLY;BYDAY=SA"
  }
}

run "defaults_are_the_recommended_position" {
  command = plan

  assert {
    condition     = google_container_cluster.socle.enable_autopilot
    error_message = "Autopilot is the only cluster mode the socle provisions."
  }

  assert {
    condition     = google_container_cluster.socle.release_channel[0].channel == "REGULAR"
    error_message = "The estate-wide default channel is REGULAR."
  }

  assert {
    condition     = google_container_cluster.socle.private_cluster_config[0].enable_private_nodes
    error_message = "Private nodes must be on by default: Autopilot's own default is public."
  }

  assert {
    condition     = !google_container_cluster.socle.control_plane_endpoints_config[0].ip_endpoints_config[0].enabled
    error_message = "IP endpoints must be off: the DNS-based endpoint is the access path."
  }

  assert {
    condition = (
      length(google_container_cluster.socle.monitoring_config[0].enable_components) == 1 &&
      contains(google_container_cluster.socle.monitoring_config[0].enable_components, "SYSTEM_COMPONENTS")
    )
    error_message = "Only the free metric component is enabled by default; everything else is billed per sample."
  }

  assert {
    condition     = google_container_cluster.socle.monitoring_config[0].managed_prometheus[0].enabled
    error_message = "Managed collection is the ingestion path and carries no fee of its own."
  }

  assert {
    condition     = google_container_cluster.socle.cost_management_config[0].enabled
    error_message = "Cost allocation must be on from day one, because it does not backfill."
  }

  assert {
    condition     = google_compute_subnetwork.socle[0].private_ip_google_access
    error_message = "Private nodes reach Google APIs over Private Google Access."
  }

  assert {
    condition     = length(google_compute_router_nat.socle) == 1
    error_message = "Cloud NAT is created by default: private nodes cannot pull an image without egress."
  }

  assert {
    condition     = length(google_compute_subnetwork.proxy_only) == 1
    error_message = "The proxy-only subnetwork is created by default, or no regional Gateway can exist."
  }

  assert {
    condition     = google_container_cluster.socle.resource_labels["socle-version"] != ""
    error_message = "Every billable resource carries the socle version that created it."
  }

  assert {
    condition     = output.workload_identity_pool == "socle-test-project.svc.id.goog"
    error_message = "The Workload Identity pool is derived from the project, not configured."
  }

  assert {
    condition     = length(google_pubsub_topic.upgrade_notifications) == 1
    error_message = "Upgrade notifications are on by default so automation can react instead of polling."
  }
}

run "an_exclusion_lands_on_the_cluster" {
  command = plan

  variables {
    maintenance_exclusions = [{
      name       = "year-end-freeze"
      start_time = "2026-12-20T00:00:00Z"
      end_time   = "2027-01-05T00:00:00Z"
      scope      = "NO_MINOR_UPGRADES"
    }]
  }

  assert {
    condition     = length(google_container_cluster.socle.maintenance_policy[0].maintenance_exclusion) == 1
    error_message = "A declared exclusion must reach the cluster's maintenance policy."
  }
}

run "attaching_to_an_existing_network_and_creating_one_is_incoherent" {
  command = plan

  variables {
    create_network = true
    network_name   = "shared-vpc"
  }

  expect_failures = [var.network_name]
}

run "neither_creating_nor_naming_a_network_is_incoherent" {
  command = plan

  variables {
    create_network = false
    network_name   = null
  }

  expect_failures = [var.network_name]
}

run "an_existing_subnetwork_needs_its_name" {
  command = plan

  variables {
    create_network    = false
    network_name      = "shared-vpc"
    create_subnetwork = false
    subnetwork_name   = null
    pod_range_name    = "pods"
  }

  expect_failures = [var.subnetwork_name]
}

run "an_existing_subnetwork_needs_its_pod_range_name" {
  command = plan

  variables {
    create_network    = false
    network_name      = "shared-vpc"
    create_subnetwork = false
    subnetwork_name   = "shared-subnet"
    pod_range_name    = null
  }

  expect_failures = [var.pod_range_name]
}

run "private_nodes_without_egress_are_refused" {
  command = plan

  variables {
    create_nat = false
  }

  expect_failures = [var.create_nat]
}
