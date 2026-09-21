# Every validation block, tripped once. Negative cases only, on purpose: this
# module talks to a cluster, and a passing plan would need one. What can be
# proven without a cluster is that the interface refuses what it should — the
# plan stops at variable validation, before the helm provider is ever reached.

variables {
  cluster_name = "socle-dev"
  environment  = "dev"
  owner        = "platform"
  sync_url     = "oci://rg.fr-par.scw.cloud/socle/socle"
  sync_ref     = "v0.1.0"
}

run "cluster_name_refuses_uppercase" {
  command = plan
  variables {
    cluster_name = "Socle-Dev"
  }
  expect_failures = [var.cluster_name]
}

run "environment_refuses_anything_else" {
  command = plan
  variables {
    environment = "uat"
  }
  expect_failures = [var.environment]
}

run "owner_refuses_spaces" {
  command = plan
  variables {
    owner = "platform team"
  }
  expect_failures = [var.owner]
}

run "cluster_type_refuses_a_cloud_that_is_not_one" {
  command = plan
  variables {
    cluster_type = "scaleway"
  }
  expect_failures = [var.cluster_type]
}

run "operator_version_refuses_a_range" {
  command = plan
  variables {
    operator_version = "0.60"
  }
  expect_failures = [var.operator_version]
}

run "flux_version_refuses_a_major_that_is_not_two" {
  command = plan
  variables {
    flux_version = "3.0.0"
  }
  expect_failures = [var.flux_version]
}

run "flux_components_refuses_an_unknown_controller" {
  command = plan
  variables {
    flux_components = ["source-controller", "kustomize-controller", "helm-controler"]
  }
  expect_failures = [var.flux_components]
}

run "flux_components_refuses_dropping_the_reconciliation_path" {
  command = plan
  variables {
    flux_components = ["source-controller", "notification-controller"]
  }
  expect_failures = [var.flux_components]
}

run "sync_url_refuses_a_bare_host" {
  command = plan
  variables {
    sync_url = "rg.fr-par.scw.cloud/socle/socle"
  }
  expect_failures = [var.sync_url]
}

run "sync_kind_refuses_an_unknown_kind" {
  command = plan
  variables {
    sync_kind = "HelmRepository"
  }
  expect_failures = [var.sync_kind]
}

run "oci_sync_refuses_an_https_url" {
  command = plan
  variables {
    sync_kind = "OCIRepository"
    sync_url  = "https://github.com/do-now-io/socle.git"
  }
  expect_failures = [var.sync_kind]
}

run "sync_ref_refuses_a_moving_head" {
  command = plan
  variables {
    sync_ref = "latest"
  }
  expect_failures = [var.sync_ref]
}

run "sync_ref_refuses_empty" {
  command = plan
  variables {
    sync_ref = ""
  }
  expect_failures = [var.sync_ref]
}

run "sync_interval_refuses_a_bare_number" {
  command = plan
  variables {
    sync_interval = "60"
  }
  expect_failures = [var.sync_interval]
}

run "cosign_verification_refuses_a_git_sync" {
  command = plan
  variables {
    sync_kind                   = "GitRepository"
    sync_url                    = "ssh://git@github.com/do-now-io/fleet.git"
    cosign_verification_enabled = true
  }
  expect_failures = [var.cosign_verification_enabled]
}

run "cosign_identity_refuses_a_half_filled_object" {
  command = plan
  variables {
    cosign_identity = {
      issuer  = "https://token.actions.githubusercontent.com"
      subject = ""
    }
  }
  expect_failures = [var.cosign_identity]
}

run "instance_size_refuses_an_invented_profile" {
  command = plan
  variables {
    instance_size = "xlarge"
  }
  expect_failures = [var.instance_size]
}

run "helm_timeout_refuses_an_unrealistic_value" {
  command = plan
  variables {
    helm_timeout_seconds = 30
  }
  expect_failures = [var.helm_timeout_seconds]
}
