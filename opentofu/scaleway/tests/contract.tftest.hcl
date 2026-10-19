# The outputs, as a root reads them. A plan leaves the cluster's computed
# attributes unknown, so these runs apply against a mocked scaleway provider:
# nothing is created, every computed attribute is a placeholder. The asserts
# check presence and wiring, never a placeholder's format (#61, M2).

mock_provider "scaleway" {
  # Every id one resource passes to another is checked as a UUID: the mock's
  # random strings are not.
  mock_resource "scaleway_cockpit_token" {
    defaults = {
      id = "00000001-0000-4000-8000-000000000000"
    }
  }
  mock_resource "scaleway_iam_api_key" {
    defaults = {
      id = "00000002-0000-4000-8000-000000000000"
    }
  }
  mock_resource "scaleway_iam_application" {
    defaults = {
      id = "00000003-0000-4000-8000-000000000000"
    }
  }
  mock_resource "scaleway_iam_policy" {
    defaults = {
      id = "00000004-0000-4000-8000-000000000000"
    }
  }
  mock_resource "scaleway_instance_placement_group" {
    defaults = {
      id = "00000005-0000-4000-8000-000000000000"
    }
  }
  mock_resource "scaleway_instance_security_group" {
    defaults = {
      id = "00000006-0000-4000-8000-000000000000"
    }
  }
  mock_resource "scaleway_ipam_ip" {
    defaults = {
      id = "00000007-0000-4000-8000-000000000000"
    }
  }
  mock_resource "scaleway_k8s_acl" {
    defaults = {
      id = "00000008-0000-4000-8000-000000000000"
    }
  }
  mock_resource "scaleway_k8s_pool" {
    defaults = {
      id = "00000009-0000-4000-8000-000000000000"
    }
  }
  mock_resource "scaleway_vpc_gateway_network" {
    defaults = {
      id = "00000010-0000-4000-8000-000000000000"
    }
  }
  mock_resource "scaleway_vpc_private_network" {
    defaults = {
      id = "00000011-0000-4000-8000-000000000000"
    }
  }
  mock_resource "scaleway_vpc_public_gateway_ip" {
    defaults = {
      id = "00000012-0000-4000-8000-000000000000"
    }
  }
  mock_resource "scaleway_vpc_public_gateway" {
    defaults = {
      id = "00000013-0000-4000-8000-000000000000"
    }
  }
  mock_resource "scaleway_vpc" {
    defaults = {
      id = "00000014-0000-4000-8000-000000000000"
    }
  }
  # Kapsule reports its endpoint, its type and its kubeconfig once the
  # cluster exists: given as a real cluster gives them.
  mock_resource "scaleway_k8s_cluster" {
    defaults = {
      id            = "00000000-0000-4000-8000-000000000000"
      apiserver_url = "https://00000000-0000-0000-0000-000000000000.api.k8s.fr-par.scw.cloud:6443"
      wildcard_dns  = "*.00000000-0000-0000-0000-000000000000.nodes.k8s.fr-par.scw.cloud"
      kubeconfig = [{
        config_file            = "apiVersion: v1\nkind: Config\n"
        host                   = "https://00000000-0000-0000-0000-000000000000.api.k8s.fr-par.scw.cloud:6443"
        cluster_ca_certificate = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCg=="
        token                  = ""
      }]
    }
  }
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

run "the_cluster_outputs_are_what_a_root_wires" {
  command = apply

  assert {
    condition     = output.cluster_id == scaleway_k8s_cluster.socle.id && output.cluster_name == "socle-test" && output.cluster_region == scaleway_k8s_cluster.socle.region && output.cluster_type == "kapsule-dedicated-4"
    error_message = "cluster_id, cluster_name, cluster_region and cluster_type are the cluster's."
  }

  assert {
    condition     = output.cluster_endpoint == "https://00000000-0000-0000-0000-000000000000.api.k8s.fr-par.scw.cloud:6443" && output.helm_kubernetes.host == output.cluster_endpoint
    error_message = "cluster_endpoint is Kapsule's API, and helm_kubernetes connects to it."
  }

  assert {
    condition     = output.cluster_ca_certificate == "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCg==" && output.kubeconfig == "apiVersion: v1\nkind: Config\n"
    error_message = "cluster_ca_certificate and kubeconfig are Kapsule's."
  }

  assert {
    condition     = output.wildcard_dns == "*.00000000-0000-0000-0000-000000000000.nodes.k8s.fr-par.scw.cloud"
    error_message = "wildcard_dns is the cluster's."
  }

  assert {
    condition     = output.oidc_issuer_url == null && output.workload_identity_pool == null
    error_message = "Kapsule has no workload identity: both are null, so a root can tell."
  }
}

run "the_identity_and_network_outputs_name_what_the_module_created" {
  command = apply

  assert {
    condition     = output.crossplane_application_id == scaleway_iam_application.crossplane.id && output.crossplane_access_key == scaleway_iam_api_key.crossplane.access_key && output.crossplane_secret_key == scaleway_iam_api_key.crossplane.secret_key
    error_message = "Crossplane's application and key are the ones the module created."
  }

  assert {
    condition     = output.cockpit_token_secret == scaleway_cockpit_token.observability[0].secret_key
    error_message = "cockpit_token_secret is the observability token's, on by default."
  }

  assert {
    condition     = output.vpc_id == scaleway_vpc.socle[0].id && output.private_network_id == scaleway_vpc_private_network.socle.id
    error_message = "vpc_id and private_network_id are what the module created."
  }

  assert {
    condition     = length(output.gateway_egress_cidrs) > 0 && length(output.security_group_ids) == 2
    error_message = "One egress address per public gateway, one security group per zone."
  }

  assert {
    condition     = contains(output.tags, "owner=platform") && contains(output.tags, "environment=prod")
    error_message = "tags carries the owner and the environment."
  }
}
