# A consumer who sets nothing gets the recommended configuration. These runs
# assert that, and that the precondition guarding an incoherent production
# cluster fires.
#
# The provider is configured with fixture credentials so the plan stays
# offline: nothing here refreshes state or reads an existing resource, so no
# API call is made.

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
  environment  = "prod"

  kubernetes_version                   = "1.35"
  cluster_endpoint_public_access_cidrs = ["203.0.113.10/32"]
  crossplane_permission_sets           = ["RelationalDatabasesFullAccess"]

  maintenance_window = {
    day        = "saturday"
    start_hour = 3
  }
}

run "defaults_are_the_recommended_position" {
  command = plan

  assert {
    condition     = scaleway_k8s_cluster.socle.cni == "cilium"
    error_message = "Cilium is the CNI. Calico is not offered and `none` is not supported on Kapsule."
  }

  assert {
    condition     = scaleway_k8s_cluster.socle.type == "kapsule-dedicated-4"
    error_message = "A production cluster must derive a dedicated control plane: the mutualized offer has no SLA and no audit logs."
  }

  assert {
    condition     = scaleway_k8s_cluster.socle.auto_upgrade[0].enable
    error_message = "Auto-upgrade must be on. It covers patches only, which is exactly the part that should not need a human."
  }

  assert {
    condition     = scaleway_k8s_cluster.socle.autoscaler_config[0].expander == "least_waste"
    error_message = "The expander must be least_waste. Scaleway ships random, which picks a pool to grow by coin flip."
  }

  assert {
    condition     = scaleway_k8s_cluster.socle.autoscaler_config[0].balance_similar_node_groups
    error_message = "Pools differ by zone, not by shape, so the autoscaler should keep them level."
  }

  assert {
    condition     = !scaleway_k8s_cluster.socle.delete_additional_resources
    error_message = "Deleting a cluster must not delete the client's volumes and load balancers by default."
  }

  assert {
    condition     = alltrue([for p in scaleway_k8s_pool.socle : p.public_ip_disabled])
    error_message = "Full isolation everywhere: no node carries a public address."
  }

  assert {
    condition     = alltrue([for p in scaleway_k8s_pool.socle : p.autohealing && p.autoscaling])
    error_message = "Every pool autoscales and autoheals."
  }

  assert {
    condition     = length(scaleway_k8s_pool.socle) == 2
    error_message = "The default spans two zones — one pool per zone — because the current instance generation exists in only two zones of fr-par."
  }

  assert {
    condition     = length(scaleway_vpc_public_gateway.socle) == length(scaleway_k8s_pool.socle)
    error_message = "One Public Gateway per zone the pools span: the gateway is zoned and has no HA of its own."
  }

  assert {
    condition     = alltrue([for g in scaleway_vpc_gateway_network.socle : g.ipam_config[0].push_default_route])
    error_message = "Every gateway must advertise a default route, or fully isolated nodes have no egress."
  }

  assert {
    condition     = alltrue([for sg in scaleway_instance_security_group.socle : sg.inbound_default_policy == "drop"])
    error_message = "The cluster's own security groups drop inbound traffic."
  }

  assert {
    condition     = length(scaleway_instance_security_group.socle) == length(scaleway_k8s_pool.socle)
    error_message = "One security group per zone: an Instance security group is zoned, so a pool can only reference one from its own zone."
  }

  assert {
    condition     = length(scaleway_k8s_acl.socle.acl_rules) == 1
    error_message = "The ACL must replace Kapsule's default 0.0.0.0/0 rule with exactly what the consumer allowed."
  }

  assert {
    condition     = scaleway_cockpit_token.observability[0].scopes[0].query_metrics && !scaleway_cockpit_token.observability[0].scopes[0].write_metrics
    error_message = "The Cockpit token reads and never writes: pushing samples into Cockpit is billed at ~2.5x GKE's rate."
  }
}

run "non_production_stays_on_the_free_control_plane" {
  command = plan

  variables {
    environment = "dev"
  }

  assert {
    condition     = scaleway_k8s_cluster.socle.type == "kapsule"
    error_message = "Dev and staging run the mutualized control plane, which is free."
  }
}

run "production_refuses_the_mutualized_control_plane" {
  command = plan

  variables {
    environment        = "prod"
    control_plane_type = "kapsule"
  }

  expect_failures = [scaleway_k8s_cluster.socle]
}

# The default derives the condition from the Public Gateways' addresses, which
# are unknown until apply — so the condition string cannot be asserted at plan
# time. Supplying the CIDRs explicitly makes it knowable and tests the same
# code path: the format() call and the CEL it emits are identical either way.
run "the_crossplane_key_is_bound_to_a_source_address" {
  command = plan

  variables {
    crossplane_allowed_cidrs = ["203.0.113.0/24", "198.51.100.7/32"]
  }

  assert {
    condition     = scaleway_iam_policy.crossplane.rule[0].condition == "request.ip in ['203.0.113.0/24', '198.51.100.7/32']"
    error_message = "The Crossplane policy must carry a request.ip condition — it is the only mitigation available for a key Scaleway gives no way to federate."
  }

  assert {
    condition     = scaleway_iam_policy.crossplane.rule[0].project_ids == tolist([var.project_id])
    error_message = "The Crossplane policy is scoped to one Project: Scaleway has no per-resource conditions for these products."
  }
}

run "a_pl_waw_estate_can_span_three_zones" {
  command = plan

  variables {
    region             = "pl-waw"
    availability_zones = ["pl-waw-1", "pl-waw-2", "pl-waw-3"]
    node_type          = "POP2-HC-8C-16G"
  }

  assert {
    condition     = length(scaleway_k8s_pool.socle) == 3
    error_message = "pl-waw is the one region where a homogeneous three-zone cluster is possible."
  }
}

run "helm_kubernetes_reads_the_secret_key_from_the_environment_at_call_time" {
  command = plan

  assert {
    condition     = output.helm_kubernetes.exec.command == "sh" && can(regex("SCW_SECRET_KEY", join(" ", output.helm_kubernetes.exec.args)))
    error_message = "Kapsule has no exec plugin; helm_kubernetes must emit an ExecCredential from SCW_SECRET_KEY at call time rather than carry the token."
  }
}
