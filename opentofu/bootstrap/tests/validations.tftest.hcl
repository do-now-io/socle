# Every validation block, tripped once. Negative cases only: the plan stops at
# variable validation, before the helm provider is ever configured, so these
# runs need no cluster.

variables {
  cloud        = "aws"
  cluster_name = "socle-test"
  environment  = "dev"
  owner        = "platform"
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
