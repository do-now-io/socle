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

# data.google_project is the one data source in this module that calls an API:
# a Workload Identity principal names the project by its number, which only
# the API knows. Stubbed rather than reached, so these runs stay
# credential-free.
override_data {
  target = data.google_project.this
  values = {
    number = "123456789012"
  }
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
    condition     = google_container_cluster.socle.gateway_api_config[0].channel == "CHANNEL_STANDARD"
    error_message = "GKE's Gateway API controller and standard-channel CRDs must be on: the socle installs nothing for Gateway API on GKE because of it."
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

run "helm_kubernetes_is_credential_free_and_uses_the_gke_exec_plugin" {
  command = plan

  assert {
    condition     = output.helm_kubernetes.exec.command == "gke-gcloud-auth-plugin"
    error_message = "helm_kubernetes must obtain its token at call time through gke-gcloud-auth-plugin, never carry one."
  }
}

run "gateway_api_can_be_switched_off" {
  command = plan

  variables {
    gateway_api_enabled = false
  }

  assert {
    condition     = google_container_cluster.socle.gateway_api_config[0].channel == "CHANNEL_DISABLED"
    error_message = "gateway_api_enabled = false must disable the GKE Gateway API channel, not leave it at the default."
  }
}

run "the_principal_carries_the_project_number" {
  command = plan

  assert {
    condition     = output.workload_identity_principal_prefix == "principal://iam.googleapis.com/projects/123456789012/locations/global/workloadIdentityPools/socle-test-project.svc.id.goog/subject"
    error_message = "a Workload Identity Federation principal names the project by its number, not its ID: a prefix built on the ID matches no workload, and every binding made with it grants nothing."
  }
  assert {
    condition     = output.project_id == "socle-test-project" && output.project_number == "123456789012" && output.region == "europe-west1"
    error_message = "the project's ID, its number and the region are what the bootstrap module builds every principal and every regional resource from."
  }
}

run "a_known_project_number_skips_the_lookup" {
  command = plan
  variables {
    project_number = "987654321098"
  }

  assert {
    condition     = length(data.google_project.this) == 0 && output.project_number == "987654321098" && startswith(output.workload_identity_principal_prefix, "principal://iam.googleapis.com/projects/987654321098/")
    error_message = "a project number the caller supplies replaces the lookup, and the principals are built on it."
  }
}

# --- crossplane — docs/catalog/crossplane.md ----------------------------------

run "crossplane_gets_no_identity_unless_asked" {
  command = plan

  assert {
    condition = (
      length(google_project_iam_member.crossplane_project_grants) == 0 &&
      length(google_project_iam_member.crossplane_buckets) == 0 &&
      length(google_dns_managed_zone_iam_member.crossplane) == 0 &&
      length(google_project_iam_custom_role.crossplane_buckets) == 0 &&
      length(google_project_iam_custom_role.crossplane_zone_iam) == 0 &&
      length(google_project_iam_custom_role.dns_zone_lister) == 0
    )
    error_message = "crossplane defaults to null: no grant, no custom role — the most powerful identity in the cluster exists only when the client asks for it."
  }
  assert {
    condition     = output.crossplane_principal == null && length(output.crossplane_dns_zones) == 0 && output.dns_zone_lister_role == ""
    error_message = "the crossplane outputs must say there is nothing: a null principal, no zone, no lister role."
  }
}

run "crossplane_identity_grants_only_bounded_roles" {
  command = plan
  variables {
    cluster_name = "socle-prod"
    crossplane   = { allowed_roles = ["roles/secretmanager.secretAccessor"] }
  }

  assert {
    condition     = google_project_iam_member.crossplane_project_grants[0].member == "principal://iam.googleapis.com/projects/123456789012/locations/global/workloadIdentityPools/socle-test-project.svc.id.goog/subject/ns/crossplane-system/sa/provider-gcp"
    error_message = "the grant must go to crossplane-system/provider-gcp, the ServiceAccount the socle artifact fixes for every GCP provider pod, as a direct principal: no Google service account."
  }
  assert {
    condition     = output.crossplane_principal == google_project_iam_member.crossplane_project_grants[0].member
    error_message = "the principal output must be the member every Crossplane grant names."
  }
  assert {
    condition     = google_project_iam_member.crossplane_project_grants[0].role == "roles/resourcemanager.projectIamAdmin"
    error_message = "project-level grants go through Project IAM Admin, the one predefined role Google documents for a limited IAM admin."
  }
  assert {
    condition     = strcontains(google_project_iam_member.crossplane_project_grants[0].condition[0].expression, "api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly([\"roles/secretmanager.secretAccessor\",\"projects/socle-test-project/roles/socleDnsZoneLister_socle_prod\"])")
    error_message = "Crossplane may grant exactly the client's allowed roles plus the socle's zone lister role, nothing else: the condition is the boundary."
  }
  assert {
    condition     = output.dns_zone_lister_role == "projects/socle-test-project/roles/socleDnsZoneLister_socle_prod"
    error_message = "the lister role's full name, built without waiting for Google, must name the role as it is created."
  }
  assert {
    condition     = toset(google_project_iam_custom_role.dns_zone_lister[0].permissions) == toset(["dns.managedZones.list", "dns.managedZones.get"])
    error_message = "the lister role lets external-dns find its zones at project level, and change nothing."
  }
}

run "crossplane_without_a_role_grants_nothing_but_the_lister" {
  command = plan
  variables {
    crossplane = {}
  }

  assert {
    condition     = endswith(google_project_iam_member.crossplane_project_grants[0].condition[0].expression, ".hasOnly([\"projects/socle-test-project/roles/socleDnsZoneLister_socle_test\"])")
    error_message = "with no role allowed, Crossplane may grant only the socle's own lister role: a module that asks for anything else fails visibly instead of being granted it."
  }
  assert {
    condition     = endswith(google_project_iam_member.crossplane_buckets[0].condition[0].expression, ".hasOnly([\"projects/socle-test-project/roles/socleDnsZoneLister_socle_test\"])")
    error_message = "the bucket grant is bounded by the same list."
  }
}

run "crossplane_roles_are_named_after_their_cluster" {
  command = plan
  variables {
    cluster_name = "socle-prod"
    crossplane   = {}
  }

  assert {
    condition = (
      google_project_iam_custom_role.crossplane_buckets[0].role_id == "socleCrossplaneBuckets_socle_prod" &&
      google_project_iam_custom_role.crossplane_zone_iam[0].role_id == "socleCrossplaneZoneIam_socle_prod" &&
      google_project_iam_custom_role.dns_zone_lister[0].role_id == "socleDnsZoneLister_socle_prod"
    )
    error_message = "custom role IDs are unique per project and take no dash: each must carry the cluster's name, dashes turned to underscores, or a second cluster in the project collides with the first."
  }
  assert {
    condition     = google_project_iam_member.crossplane_project_grants[0].condition[0].title == "socle-socle-prod-grants-only-allowed-roles" && google_project_iam_member.crossplane_buckets[0].condition[0].title == "socle-socle-prod-own-buckets"
    error_message = "the conditions carry the cluster's name too, so two clusters' bindings stay apart in the project's policy."
  }
}

run "crossplane_binds_only_the_listed_zones" {
  command = plan
  variables {
    crossplane = { dns_zones = ["zone-a", "zone-b"] }
  }

  assert {
    condition     = toset(keys(google_dns_managed_zone_iam_member.crossplane)) == toset(["zone-a", "zone-b"]) && alltrue([for b in google_dns_managed_zone_iam_member.crossplane : b.role == "projects/socle-test-project/roles/socleCrossplaneZoneIam_socle_test" && length(b.condition) == 0])
    error_message = "zone IAM is granted on each listed zone and nowhere else, without a condition: Cloud DNS does not recognise modifiedGrantsByRole and would refuse every request under one."
  }
  assert {
    condition     = toset(google_project_iam_custom_role.crossplane_zone_iam[0].permissions) == toset(["dns.managedZones.get", "dns.managedZones.getIamPolicy", "dns.managedZones.setIamPolicy"])
    error_message = "on a zone Crossplane may read and set its IAM policy, and touch no record."
  }
  assert {
    condition     = output.crossplane_dns_zones == tolist(["zone-a", "zone-b"])
    error_message = "the zones Crossplane may bind on are handed on to the bootstrap module, for external-dns."
  }
}

run "buckets_are_bounded_to_the_cluster_prefix_and_never_deleted" {
  command = plan
  variables {
    crossplane = { allowed_roles = ["roles/storage.objectAdmin"] }
  }

  assert {
    condition     = google_project_iam_member.crossplane_buckets[0].role == "projects/socle-test-project/roles/socleCrossplaneBuckets_socle_test"
    error_message = "buckets are reached through the cluster's own custom role."
  }
  assert {
    condition     = startswith(google_project_iam_member.crossplane_buckets[0].condition[0].expression, "resource.name.startsWith('projects/_/buckets/socle-test-') && ")
    error_message = "Crossplane may create and manage buckets only under the cluster's own name prefix."
  }
  assert {
    condition     = strcontains(google_project_iam_member.crossplane_buckets[0].condition[0].expression, ".hasOnly([\"roles/storage.objectAdmin\",\"projects/socle-test-project/roles/socleDnsZoneLister_socle_test\"])")
    error_message = "a bucket's IAM policy is bounded by the same allowed roles as the project's."
  }
  assert {
    condition     = !anytrue([for p in google_project_iam_custom_role.crossplane_buckets[0].permissions : p == "storage.buckets.delete" || startswith(p, "storage.objects.") || startswith(p, "storage.managedFolders.")])
    error_message = "the Crossplane identity must never delete a bucket, nor read or write anything in it: a bucket of backups outlives every managed resource."
  }
  assert {
    condition     = contains(google_project_iam_custom_role.crossplane_buckets[0].permissions, "storage.buckets.create") && contains(google_project_iam_custom_role.crossplane_buckets[0].permissions, "storage.buckets.setIamPolicy")
    error_message = "a module's bucket is created by Crossplane, and bound to the module's own principal by it."
  }
}

# --- The shared Gateways' certificate — certificate.tf ---

run "no_certificate_unless_asked" {
  command = plan

  assert {
    condition = (
      length(google_certificate_manager_certificate.gateway) == 0 &&
      length(google_certificate_manager_certificate.gateway_regional) == 0 &&
      length(google_certificate_manager_dns_authorization.gateway) == 0 &&
      length(google_dns_record_set.gateway_certificate_authorization) == 0 &&
      output.gateway_certificate_map == "" && output.gateway_regional_certificate == ""
    )
    error_message = "without gateway_certificate nothing is issued, and the bootstrap module must be told so by empty names."
  }
}

run "certificate_map_covers_every_domain" {
  command = plan
  variables {
    gateway_certificate = {
      dns_zone = "sandbox-gcp-do-now-io"
      domains  = ["sandbox-gcp.do-now.io", "*.sandbox-gcp.do-now.io"]
    }
  }

  assert {
    condition     = toset(google_certificate_manager_certificate.gateway[0].managed[0].domains) == toset(["sandbox-gcp.do-now.io", "*.sandbox-gcp.do-now.io"]) && toset(google_certificate_manager_certificate.gateway_regional[0].managed[0].domains) == toset(["sandbox-gcp.do-now.io", "*.sandbox-gcp.do-now.io"])
    error_message = "both certificates must cover every listed domain, wildcard included: every route on either Gateway is <name>.<domain>."
  }
  assert {
    condition     = length(google_certificate_manager_dns_authorization.gateway) == 1 && length(google_certificate_manager_dns_authorization.gateway_regional) == 1
    error_message = "a domain and its wildcard share one DNS authorization, on the apex: one global, one regional."
  }
  assert {
    condition     = alltrue([for a in google_certificate_manager_dns_authorization.gateway_regional : a.location == "europe-west1" && a.type == "PER_PROJECT_RECORD"])
    error_message = "a regional certificate takes regional DNS authorizations only, and only of the PER_PROJECT_RECORD type."
  }
  assert {
    condition     = google_certificate_manager_certificate.gateway_regional[0].location == "europe-west1" && output.gateway_regional_certificate == google_certificate_manager_certificate.gateway_regional[0].name
    error_message = "the internal Gateway is regional: its certificate lives in the cluster's region, and its name is what the bootstrap module receives."
  }
  assert {
    condition     = toset([for e in google_certificate_manager_certificate_map_entry.gateway : e.hostname]) == toset(["sandbox-gcp.do-now.io", "*.sandbox-gcp.do-now.io"]) && alltrue([for e in google_certificate_manager_certificate_map_entry.gateway : e.map == google_certificate_manager_certificate_map.gateway[0].name])
    error_message = "the map must carry one hostname entry per domain: a name without an entry gets no certificate at the global load balancer."
  }
  assert {
    condition     = output.gateway_certificate_map == google_certificate_manager_certificate_map.gateway[0].name
    error_message = "the map's name is what the public Gateway's networking.gke.io/certmap annotation takes."
  }
  assert {
    condition     = length(google_dns_record_set.gateway_certificate_authorization) == 2 && alltrue([for r in google_dns_record_set.gateway_certificate_authorization : r.managed_zone == "sandbox-gcp-do-now-io" && r.type == "CNAME"])
    error_message = "each authorization's CNAME, global and regional, must be written into the client's zone, or neither certificate is ever issued."
  }
}
