# One failing-input case per validation block. A validation nobody tested is a
# validation nobody knows works.
#
# A static access token keeps these runs credential-free: variable validation
# fires before the plan graph, but the provider still has to be configurable,
# and without this it goes looking for application default credentials.

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
  environment  = "dev"

  create_network = true

  maintenance_window = {
    start_time = "2026-01-03T02:00:00Z"
    end_time   = "2026-01-03T14:00:00Z"
    recurrence = "FREQ=WEEKLY;BYDAY=SA"
  }
}

# --- Identity of the deployment -------------------------------------------

run "project_id_must_look_like_a_project" {
  command = plan

  variables {
    project_id = "Nope"
  }

  expect_failures = [var.project_id]
}

run "region_must_not_be_a_zone" {
  command = plan

  variables {
    region = "europe-west1-b"
  }

  expect_failures = [var.region]
}

run "cluster_name_must_be_a_dns_label" {
  command = plan

  variables {
    cluster_name = "Socle_Test"
  }

  expect_failures = [var.cluster_name]
}

run "owner_must_be_a_valid_label_value" {
  command = plan

  variables {
    owner = "Platform Team"
  }

  expect_failures = [var.owner]
}

run "environment_is_a_closed_set" {
  command = plan

  variables {
    environment = "preprod"
  }

  expect_failures = [var.environment]
}

run "additional_labels_cannot_shadow_the_standard_set" {
  command = plan

  variables {
    additional_labels = {
      owner = "someone-else"
    }
  }

  expect_failures = [var.additional_labels]
}

# --- Network ---------------------------------------------------------------

run "node_range_must_be_a_cidr" {
  command = plan

  variables {
    node_range_cidr = "10.0.0.0"
  }

  expect_failures = [var.node_range_cidr]
}

run "pod_range_must_be_a_cidr" {
  command = plan

  variables {
    pod_range_cidr = "not-a-cidr"
  }

  expect_failures = [var.pod_range_cidr]
}

run "pod_range_smaller_than_a_slash_17_is_rejected" {
  command = plan

  variables {
    pod_range_cidr = "10.4.0.0/20"
  }

  expect_failures = [var.pod_range_cidr]
}

run "proxy_only_range_smaller_than_a_slash_26_is_rejected" {
  command = plan

  variables {
    proxy_only_range_cidr = "10.8.0.0/28"
  }

  expect_failures = [var.proxy_only_range_cidr]
}

run "network_name_and_create_network_are_mutually_exclusive" {
  command = plan

  variables {
    network_name = "an-existing-vpc"
  }

  expect_failures = [var.network_name]
}

run "subnetwork_name_is_required_without_create_subnetwork" {
  command = plan

  variables {
    create_subnetwork = false
    pod_range_name    = "someone-elses-pods"
  }

  expect_failures = [var.subnetwork_name]
}

run "pod_range_name_is_required_without_create_subnetwork" {
  command = plan

  variables {
    create_subnetwork = false
    subnetwork_name   = "an-existing-subnet"
  }

  expect_failures = [var.pod_range_name]
}

run "private_nodes_on_an_owned_subnetwork_cannot_go_without_nat" {
  command = plan

  variables {
    create_nat = false
  }

  expect_failures = [var.create_nat]
}

# --- Upgrades --------------------------------------------------------------

run "extended_channel_is_rejected_because_autopilot_forbids_it" {
  command = plan

  variables {
    release_channel = "EXTENDED"
  }

  expect_failures = [var.release_channel]
}

run "unknown_channel_is_rejected" {
  command = plan

  variables {
    release_channel = "regular"
  }

  expect_failures = [var.release_channel]
}

run "maintenance_window_needs_real_timestamps" {
  command = plan

  variables {
    maintenance_window = {
      start_time = "saturday"
      end_time   = "sunday"
      recurrence = "FREQ=WEEKLY;BYDAY=SA"
    }
  }

  expect_failures = [var.maintenance_window]
}

run "maintenance_window_shorter_than_four_hours_is_rejected" {
  command = plan

  variables {
    maintenance_window = {
      start_time = "2026-01-03T02:00:00Z"
      end_time   = "2026-01-03T04:59:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SA"
    }
  }

  expect_failures = [var.maintenance_window]
}

run "maintenance_window_needs_a_recurrence_gke_understands" {
  command = plan

  variables {
    maintenance_window = {
      start_time = "2026-01-03T02:00:00Z"
      end_time   = "2026-01-03T14:00:00Z"
      recurrence = "every-saturday"
    }
  }

  expect_failures = [var.maintenance_window]
}

run "exclusion_scope_is_a_closed_set" {
  command = plan

  variables {
    maintenance_exclusions = [{
      name       = "freeze"
      start_time = "2026-12-20T00:00:00Z"
      end_time   = "2027-01-05T00:00:00Z"
      scope      = "NO_PATCH_UPGRADES"
    }]
  }

  expect_failures = [var.maintenance_exclusions]
}

run "no_upgrades_exclusion_longer_than_ninety_days_is_rejected" {
  command = plan

  variables {
    maintenance_exclusions = [{
      name       = "long-freeze"
      start_time = "2026-01-01T00:00:00Z"
      end_time   = "2026-06-01T00:00:00Z"
      scope      = "NO_UPGRADES"
    }]
  }

  expect_failures = [var.maintenance_exclusions]
}

run "more_than_three_no_upgrades_exclusions_is_rejected" {
  command = plan

  variables {
    maintenance_exclusions = [
      { name = "a", start_time = "2026-01-01T00:00:00Z", end_time = "2026-01-10T00:00:00Z", scope = "NO_UPGRADES" },
      { name = "b", start_time = "2026-02-01T00:00:00Z", end_time = "2026-02-10T00:00:00Z", scope = "NO_UPGRADES" },
      { name = "c", start_time = "2026-03-01T00:00:00Z", end_time = "2026-03-10T00:00:00Z", scope = "NO_UPGRADES" },
      { name = "d", start_time = "2026-04-01T00:00:00Z", end_time = "2026-04-10T00:00:00Z", scope = "NO_UPGRADES" },
    ]
  }

  expect_failures = [var.maintenance_exclusions]
}

run "more_than_twenty_exclusions_is_rejected" {
  command = plan

  variables {
    maintenance_exclusions = [
      for i in range(21) : {
        name       = "freeze-${i}"
        start_time = "2026-01-01T00:00:00Z"
        end_time   = "2026-01-05T00:00:00Z"
        scope      = "NO_MINOR_UPGRADES"
      }
    ]
  }

  expect_failures = [var.maintenance_exclusions]
}

# --- Observability ---------------------------------------------------------

run "logging_cannot_drop_system_components" {
  command = plan

  variables {
    logging_components = ["WORKLOADS"]
  }

  expect_failures = [var.logging_components]
}

run "logging_rejects_an_unknown_component" {
  command = plan

  variables {
    logging_components = ["SYSTEM_COMPONENTS", "EVERYTHING"]
  }

  expect_failures = [var.logging_components]
}

run "monitoring_cannot_drop_system_components" {
  command = plan

  variables {
    monitoring_components = ["APISERVER"]
  }

  expect_failures = [var.monitoring_components]
}

run "monitoring_rejects_an_unknown_component" {
  command = plan

  variables {
    monitoring_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  expect_failures = [var.monitoring_components]
}

run "observability_readers_must_be_qualified_principals" {
  command = plan

  variables {
    observability_reader_members = ["reader@example.iam.gserviceaccount.com"]
  }

  expect_failures = [var.observability_reader_members]
}
