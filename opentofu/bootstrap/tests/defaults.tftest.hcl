# A consumer who sets nothing gets the recommended configuration, and what he
# sets is normalised against the catalog before it leaves OpenTofu. The helm
# provider is mocked: these runs plan without a cluster.

mock_provider "helm" {}

variables {
  cloud        = "aws"
  cluster_name = "socle-test"
  environment  = "dev"
  owner        = "platform"
}

run "defaults_are_the_recommended_position" {
  command = plan

  assert {
    condition     = output.socle_version == "0.1.0" # x-release-please-version
    error_message = "socle_version must default to the module's own version, so one tag bump moves module and artifact together."
  }
  assert {
    condition     = output.inputs.socle.url == "oci://ghcr.io/do-now-io/socle/flux-modules"
    error_message = "the artifact URL must default to the socle registry."
  }
  assert {
    condition     = output.inputs.socle.pullSecret == ""
    error_message = "a public registry needs no pull secret; the default must be empty."
  }
  assert {
    condition     = output.inputs.modules.hello.enabled == true && output.inputs.modules.hello.replicas == 1
    error_message = "a module absent from kube must be at its catalog defaults."
  }
  assert {
    condition     = can(regex("refs/heads/main\\$$", output.cosign_identity.subject))
    error_message = "the default cosign identity must trust the release workflow on main only."
  }
  assert {
    condition     = yamldecode(helm_release.instance.values[0]).instance.cluster.type == "aws"
    error_message = "cloud=aws must wire the operator's aws cluster type."
  }
  assert {
    condition     = !can(yamldecode(helm_release.instance.values[0]).instance.sync)
    error_message = "the FluxInstance must carry no sync block: the root source is our own ResourceSet."
  }
}

run "client_values_are_merged_over_catalog_defaults" {
  command = plan
  variables {
    kube = { hello = { replicas = 3 } }
  }

  assert {
    condition     = output.inputs.modules.hello.replicas == 3
    error_message = "a value the client sets must win."
  }
  assert {
    condition     = output.inputs.modules.hello.enabled == true && output.inputs.modules.hello.message == "hello from socle"
    error_message = "attributes the client did not set must keep the catalog default: templates test values, never presence."
  }
}

run "scaleway_is_a_plain_kubernetes_cluster_for_the_operator" {
  command = plan
  variables { cloud = "scaleway" }

  assert {
    condition     = yamldecode(helm_release.instance.values[0]).instance.cluster.type == "kubernetes"
    error_message = "Scaleway has no workload identity federation the operator knows; cluster.type must be kubernetes."
  }
  assert {
    condition     = output.inputs.cloud == "scaleway"
    error_message = "inputs.cloud must carry the socle's own cloud name, which the artifact's clusters/<cloud> path uses."
  }
}

run "a_pinned_version_flows_to_the_inputs" {
  command = plan
  variables { socle_version = "0.0.0-feat-x.abc1234" }

  assert {
    condition     = output.inputs.socle.version == "0.0.0-feat-x.abc1234"
    error_message = "socle_version must override the module's own version, for a dev cluster testing a branch build."
  }
}

run "a_null_override_means_the_default_never_no_verification" {
  command = plan
  variables {
    cosign_identity = null
    artifact_url    = null
    kube            = null
  }

  assert {
    condition     = can(regex("refs/heads/main\\$$", output.cosign_identity.subject)) && output.inputs.socle.url == "oci://ghcr.io/do-now-io/socle/flux-modules" && output.inputs.modules.hello.enabled == true
    error_message = "null on an overridable input must mean the module's default — the release identity on main, the socle registry, the catalog defaults — never an absent value."
  }
}
