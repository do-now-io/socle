# One failing-input case per validation block. A validation nobody tested is a
# validation nobody knows works.
#
# Fixture credentials keep these runs offline: variable validation fires before
# the plan graph, but the provider still has to be configurable.

provider "scaleway" {
  access_key      = "SCWXXXXXXXXXXXXXXXXX"
  secret_key      = "11111111-1111-1111-1111-111111111111"
  project_id      = "22222222-2222-2222-2222-222222222222"
  organization_id = "33333333-3333-3333-3333-333333333333"
  region          = "fr-par"
  zone            = "fr-par-1"
}

variables {
  project_id   = "22222222-2222-2222-2222-222222222222"
  cluster_name = "socle-test"
  owner        = "platform"
  environment  = "dev"

  kubernetes_version                   = "1.35"
  cluster_endpoint_public_access_cidrs = ["203.0.113.10/32"]
  crossplane_permission_sets           = ["RelationalDatabasesFullAccess"]

  maintenance_window = {
    day        = "tuesday"
    start_hour = 3
  }
}

# --- Identity of the deployment -------------------------------------------

run "project_id_must_be_a_uuid" {
  command = plan
  variables { project_id = "my-project" }

  expect_failures = [var.project_id]
}

run "region_must_be_a_scaleway_region" {
  command = plan
  variables { region = "eu-west-1" }

  expect_failures = [var.region]
}

run "cluster_name_must_be_a_dns_label" {
  command = plan
  variables { cluster_name = "Socle_Test" }

  expect_failures = [var.cluster_name]
}

run "owner_must_be_a_tag_value" {
  command = plan
  variables { owner = "Platform Team" }

  expect_failures = [var.owner]
}

run "environment_must_be_known" {
  command = plan
  variables { environment = "uat" }

  expect_failures = [var.environment]
}

run "additional_tags_must_not_shadow_the_standard_set" {
  command = plan
  variables { additional_tags = { owner = "someone-else" } }

  expect_failures = [var.additional_tags]
}

# --- Network ---------------------------------------------------------------

run "vpc_id_and_create_vpc_are_mutually_exclusive" {
  command = plan

  variables {
    create_vpc = true
    vpc_id     = "44444444-4444-4444-4444-444444444444"
  }

  expect_failures = [var.vpc_id]
}

run "attaching_to_an_existing_vpc_needs_its_id" {
  command = plan

  variables {
    create_vpc = false
    vpc_id     = null
  }

  expect_failures = [var.vpc_id]
}

run "private_network_cidr_must_be_a_slash_22" {
  command = plan
  variables { private_network_cidr = "10.10.0.0/16" }

  expect_failures = [var.private_network_cidr]
}

run "availability_zones_must_not_repeat" {
  command = plan
  variables { availability_zones = ["fr-par-1", "fr-par-1"] }

  expect_failures = [var.availability_zones]
}

run "availability_zones_must_be_real_zones" {
  command = plan
  variables { availability_zones = ["fr-par-9"] }

  expect_failures = [var.availability_zones]
}

run "availability_zones_must_belong_to_the_region" {
  command = plan

  variables {
    region             = "fr-par"
    availability_zones = ["pl-waw-1"]
  }

  expect_failures = [var.availability_zones]
}

run "public_gateway_type_must_be_an_offer" {
  command = plan
  variables { public_gateway_type = "VPC-GW-XXL" }

  expect_failures = [var.public_gateway_type]
}

# --- Control plane access --------------------------------------------------

run "the_allow_list_must_not_be_empty" {
  command = plan
  variables { cluster_endpoint_public_access_cidrs = [] }

  expect_failures = [var.cluster_endpoint_public_access_cidrs]
}

run "the_allow_list_must_hold_cidrs" {
  command = plan
  variables { cluster_endpoint_public_access_cidrs = ["203.0.113.10"] }

  expect_failures = [var.cluster_endpoint_public_access_cidrs]
}

run "the_allow_list_refuses_the_whole_internet" {
  command = plan
  variables { cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"] }

  expect_failures = [var.cluster_endpoint_public_access_cidrs]
}

# --- Cluster ---------------------------------------------------------------

run "kubernetes_version_must_look_like_a_version" {
  command = plan
  variables { kubernetes_version = "latest" }

  expect_failures = [var.kubernetes_version]
}

run "control_plane_type_refuses_kosmos" {
  command = plan
  variables { control_plane_type = "multicloud" }

  expect_failures = [var.control_plane_type]
}

run "maintenance_window_day_must_be_a_day" {
  command = plan

  variables {
    maintenance_window = {
      day        = "Caturday"
      start_hour = 3
    }
  }

  expect_failures = [var.maintenance_window]
}

run "maintenance_window_hour_must_be_an_hour" {
  command = plan

  variables {
    maintenance_window = {
      day        = "tuesday"
      start_hour = 25
    }
  }

  expect_failures = [var.maintenance_window]
}

run "autoscaler_expander_refuses_price" {
  command = plan
  variables { autoscaler_expander = "price" }

  expect_failures = [var.autoscaler_expander]
}

run "scale_down_unneeded_time_must_be_a_duration" {
  command = plan
  variables { scale_down_unneeded_time = "ten minutes" }

  expect_failures = [var.scale_down_unneeded_time]
}

run "scale_down_utilization_threshold_must_be_a_fraction" {
  command = plan
  variables { scale_down_utilization_threshold = 1.5 }

  expect_failures = [var.scale_down_utilization_threshold]
}

# --- Node pools ------------------------------------------------------------

run "node_type_refuses_shared_vcpu_ranges" {
  command = plan
  variables { node_type = "BASIC3-X8C-16G" }

  expect_failures = [var.node_type]
}

# The finding this encodes: the Zen 5 ranges and the POP2 generation never
# share an Availability Zone.
run "zen5_node_types_refuse_a_zone_that_has_none" {
  command = plan

  variables {
    availability_zones = ["fr-par-3"]
    node_type          = "COMPUTE3-X8C-16G"
  }

  expect_failures = [var.node_type]
}

run "pop2_node_types_refuse_a_zone_that_has_none" {
  command = plan

  variables {
    availability_zones = ["fr-par-1"]
    node_type          = "POP2-HC-8C-16G"
  }

  expect_failures = [var.node_type]
}

run "pool_max_size_must_not_sit_below_the_minimum" {
  command = plan

  variables {
    pool_min_size = 4
    pool_max_size = 2
  }

  expect_failures = [var.pool_max_size]
}

run "root_volume_must_hold_the_system" {
  command = plan
  variables { root_volume_size_in_gb = 10 }

  expect_failures = [var.root_volume_size_in_gb]
}

# --- Identities ------------------------------------------------------------

run "crossplane_needs_at_least_one_permission_set" {
  command = plan
  variables { crossplane_permission_sets = [] }

  expect_failures = [var.crossplane_permission_sets]
}

run "crossplane_refuses_full_organization_access" {
  command = plan
  variables { crossplane_permission_sets = ["AllProductsFullAccess"] }

  expect_failures = [var.crossplane_permission_sets]
}

run "crossplane_key_expiry_must_be_a_timestamp" {
  command = plan
  variables { crossplane_key_expires_at = "next year" }

  expect_failures = [var.crossplane_key_expires_at]
}

run "crossplane_allowed_cidrs_must_be_cidrs" {
  command = plan
  variables { crossplane_allowed_cidrs = ["203.0.113.10"] }

  expect_failures = [var.crossplane_allowed_cidrs]
}
