# Every validation block, tripped once. Negative cases only: the plan stops at
# variable validation, before the helm provider is ever configured, so these
# runs need no cluster.

variables {
  cloud        = "aws"
  cluster_name = "socle-test"
  environment  = "dev"
  owner        = "platform"

  cluster_network = {
    api_endpoint = "https://ABCDEF.gr7.eu-west-3.eks.amazonaws.com"
    service_cidr = "172.20.0.0/16"
    pod_cidr     = "10.244.0.0/16"
  }
}

run "cloud_refuses_a_value_that_is_not_one_of_ours" {
  command = plan
  variables { cloud = "kubernetes" }
  expect_failures = [var.cloud]
}

run "cluster_name_refuses_uppercase" {
  command = plan
  variables { cluster_name = "Socle-Test" }
  expect_failures = [var.cluster_name]
}

run "environment_refuses_anything_else" {
  command = plan
  variables { environment = "uat" }
  expect_failures = [var.environment]
}

run "owner_refuses_spaces" {
  command = plan
  variables { owner = "platform team" }
  expect_failures = [var.owner]
}

run "kube_refuses_a_module_that_is_not_an_object" {
  command = plan
  variables { kube = { hello = "yes" } }
  expect_failures = [var.kube]
}

run "kube_refuses_an_unknown_module" {
  command = plan
  variables { kube = { helo = {} } }
  expect_failures = [var.kube]
}

run "kube_refuses_an_unknown_attribute" {
  command = plan
  variables { kube = { hello = { replica = 3 } } }
  expect_failures = [var.kube]
}

run "kube_refuses_enabled_that_is_not_a_bool" {
  command = plan
  variables { kube = { hello = { enabled = "yes please" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_an_attribute_of_the_wrong_type" {
  command = plan
  variables { kube = { hello = { replicas = "three" } } }
  expect_failures = [var.kube]
}

run "cilium_refuses_a_value_that_is_not_an_object" {
  command = plan
  variables { cilium = "yes" }
  expect_failures = [var.cilium]
}

run "cilium_refuses_an_unknown_attribute" {
  command = plan
  variables { cilium = { hubbel = true } }
  expect_failures = [var.cilium]
}

run "cilium_refuses_an_attribute_of_the_wrong_type" {
  command = plan
  variables { cilium = { hubble = "yes" } }
  expect_failures = [var.cilium]
}

run "cilium_is_refused_where_the_cloud_operates_it" {
  command = plan
  variables {
    cloud           = "gcp"
    cilium          = { hubble = true }
    cluster_network = null
  }
  expect_failures = [var.cilium]
}

run "cilium_refuses_values_that_are_not_an_object" {
  command = plan
  variables { cilium = { values = "hubble: {}" } }
  expect_failures = [var.cilium]
}

run "cilium_refuses_a_hubble_private_key_in_values" {
  command = plan
  variables { cilium = { values = { hubble = { tls = { server = { cert = "LS0t", key = "LS0t" } } } } } }
  expect_failures = [var.cilium]
}

run "cilium_refuses_the_ca_private_key_in_values" {
  command = plan
  variables { cilium = { values = { tls = { ca = { cert = "LS0t", key = "LS0t" } } } } }
  expect_failures = [var.cilium]
}

run "cilium_refuses_a_clustermesh_client_key_in_values" {
  command = plan
  variables { cilium = { values = { clustermesh = { config = { enabled = true, clusters = [{ name = "peer", tls = { cert = "LS0t", key = "LS0t" } }] } } } } }
  expect_failures = [var.cilium]
}

run "coredns_refuses_an_unknown_attribute" {
  command = plan
  variables { coredns = { replicas = 3 } }
  expect_failures = [var.coredns]
}

run "coredns_refuses_values_that_are_not_an_object" {
  command = plan
  variables { coredns = { values = ["replicaCount: 3"] } }
  expect_failures = [var.coredns]
}

run "coredns_is_refused_where_the_socle_installs_none" {
  command = plan
  variables {
    cloud = "azure"
    cluster_network = {
      api_endpoint = "socle-test-abc123.privatelink.westeurope.azmk8s.io"
      pod_cidr     = "10.244.0.0/16"
    }
    coredns = { values = { replicaCount = 3 } }
  }
  expect_failures = [var.coredns]
}

run "cluster_network_is_required_where_the_socle_installs_cilium" {
  command = plan
  variables { cluster_network = null }
  expect_failures = [var.cluster_network]
}

run "cluster_network_needs_the_service_cidr_on_aws" {
  command = plan
  variables {
    cluster_network = { api_endpoint = "https://ABCDEF.gr7.eu-west-3.eks.amazonaws.com" }
  }
  expect_failures = [var.cluster_network]
}

run "cluster_network_needs_the_pod_cidr_on_azure" {
  command = plan
  variables {
    cloud           = "azure"
    cluster_network = { api_endpoint = "socle-test-abc123.privatelink.westeurope.azmk8s.io" }
  }
  expect_failures = [var.cluster_network]
}

run "cluster_network_refuses_an_endpoint_that_is_not_a_host" {
  command = plan
  variables {
    cluster_network = {
      api_endpoint = "ftp://ABCDEF.gr7.eu-west-3.eks.amazonaws.com"
      service_cidr = "172.20.0.0/16"
    }
  }
  expect_failures = [var.cluster_network]
}

run "kube_refuses_a_module_not_offered_on_this_cloud" {
  command = plan
  variables {
    cloud           = "gcp"
    cluster_network = null
    kube            = { gateway_api = { enabled = false } }
  }
  expect_failures = [var.kube]
}

run "socle_version_refuses_a_moving_head" {
  command = plan
  variables { socle_version = "latest" }
  expect_failures = [var.socle_version]
}

run "socle_version_refuses_a_non_semver" {
  command = plan
  variables { socle_version = "v1" }
  expect_failures = [var.socle_version]
}

run "artifact_url_refuses_a_non_oci_url" {
  command = plan
  variables { artifact_url = "https://ghcr.io/do-now-io/socle/flux-modules" }
  expect_failures = [var.artifact_url]
}

run "artifact_pull_secret_refuses_an_invalid_secret_name" {
  command = plan
  variables { artifact_pull_secret = "Ghcr_Auth" }
  expect_failures = [var.artifact_pull_secret]
}

run "cosign_identity_refuses_an_empty_subject" {
  command = plan
  variables {
    cosign_identity = {
      issuer  = "^https://token\\.actions\\.githubusercontent\\.com$"
      subject = ""
    }
  }
  expect_failures = [var.cosign_identity]
}

run "operator_version_refuses_a_range" {
  command = plan
  variables { operator_version = "0.60" }
  expect_failures = [var.operator_version]
}

run "flux_version_refuses_a_major_that_is_not_two" {
  command = plan
  variables { flux_version = "3.0.0" }
  expect_failures = [var.flux_version]
}

run "flux_components_refuses_an_unknown_controller" {
  command = plan
  variables { flux_components = ["source-controller", "kustomize-controller", "helm-controler"] }
  expect_failures = [var.flux_components]
}

run "flux_components_refuses_dropping_the_reconciliation_path" {
  command = plan
  variables { flux_components = ["source-controller", "notification-controller"] }
  expect_failures = [var.flux_components]
}

run "instance_size_refuses_an_invented_profile" {
  command = plan
  variables { instance_size = "xlarge" }
  expect_failures = [var.instance_size]
}

run "helm_timeout_refuses_an_unrealistic_value" {
  command = plan
  variables { helm_timeout_seconds = 30 }
  expect_failures = [var.helm_timeout_seconds]
}
