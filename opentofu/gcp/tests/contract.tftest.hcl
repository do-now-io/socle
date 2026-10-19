# The outputs, as the cluster root and the bootstrap module read them. A plan
# leaves the cluster's endpoints unknown, so these runs apply against a mocked
# google provider: nothing is created, every computed attribute is a
# placeholder. The asserts check presence and wiring, never a placeholder's
# format (#61, M2).

mock_provider "google" {
  mock_data "google_project" {
    defaults = {
      number = "123456789012"
    }
  }
  # GKE reports its endpoint once the cluster exists: given as a real cluster
  # gives it. The CA sits in master_auth, a block the module configures and
  # a mock cannot override: asserted to be the cluster's.
  mock_resource "google_container_cluster" {
    defaults = {
      endpoint = "203.0.113.10"
    }
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

run "the_cluster_outputs_are_what_a_root_wires" {
  command = apply

  assert {
    condition     = output.cluster_name == "socle-test" && output.cluster_location == "europe-west1"
    error_message = "cluster_name and cluster_location are the regional cluster's."
  }

  assert {
    condition     = output.cluster_endpoint == "203.0.113.10" && output.cluster_ca_certificate == google_container_cluster.socle.master_auth[0].cluster_ca_certificate
    error_message = "cluster_endpoint and cluster_ca_certificate are GKE's, for a client on the IP endpoint."
  }

  assert {
    condition     = output.helm_kubernetes.host == "https://${output.cluster_dns_endpoint}"
    error_message = "helm_kubernetes connects to the DNS endpoint cluster_dns_endpoint names."
  }

  assert {
    condition     = output.oidc_issuer_url == "https://container.googleapis.com/v1/projects/socle-test-project/locations/europe-west1/clusters/socle-test"
    error_message = "oidc_issuer_url is the regional cluster's issuer."
  }
}

run "the_network_outputs_name_what_the_module_created" {
  command = apply

  assert {
    condition     = output.network_name == google_compute_network.socle[0].name && output.subnetwork_name == google_compute_subnetwork.socle[0].name
    error_message = "network_name and subnetwork_name are the network and subnetwork the module created."
  }

  assert {
    condition     = output.pod_range_name == "socle-test-pods"
    error_message = "pod_range_name defaults to <cluster>-pods."
  }

  assert {
    condition     = output.proxy_only_subnetwork_name == google_compute_subnetwork.proxy_only[0].name
    error_message = "proxy_only_subnetwork_name is the proxy-only subnetwork, created by default."
  }

  assert {
    condition     = output.upgrade_notifications_topic == google_pubsub_topic.upgrade_notifications[0].id
    error_message = "upgrade_notifications_topic is the topic GKE publishes upgrades to, on by default."
  }

  assert {
    condition     = output.billing_export_dataset == null
    error_message = "No billing export dataset unless billing_export_dataset_id is set."
  }
}

run "the_optional_outputs_follow_their_inputs" {
  command = apply

  variables {
    create_proxy_only_subnet     = false
    enable_upgrade_notifications = false
    billing_export_dataset_id    = "socle_billing"
  }

  assert {
    condition     = output.proxy_only_subnetwork_name == null && output.upgrade_notifications_topic == null
    error_message = "No proxy-only subnetwork and no topic when they are turned off."
  }

  assert {
    condition     = output.billing_export_dataset == google_bigquery_dataset.billing_export[0].id
    error_message = "billing_export_dataset is the dataset the module created."
  }
}
