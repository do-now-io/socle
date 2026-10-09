# A consumer who sets nothing gets the recommended configuration, and what he
# sets is normalised against the catalog before it leaves OpenTofu. The helm
# and aws providers are mocked: these runs plan without a cluster or an
# account.

mock_provider "helm" {}
mock_provider "aws" {
  # The add-ons' pod_identity_association validates the role ARN it is
  # given; the mock's random string is not one.
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::000000000000:role/socle-test-mock" }
  }
  # inputs.cluster.accountId: a module's bucket name carries it.
  mock_data "aws_caller_identity" {
    defaults = { account_id = "000000000000" }
  }
}

variables {
  cloud        = "aws"
  cluster_name = "socle-test"
  environment  = "dev"
  owner        = "platform"

  # What a root passes from its foundations' outputs, known here so the
  # rendered values can be asserted; unknown at plan on a real first apply.
  cluster_network = {
    api_endpoint = "https://ABCDEF.gr7.eu-west-3.eks.amazonaws.com"
    service_cidr = "172.20.0.0/16"
    pod_cidr     = "10.244.0.0/16"
  }
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
    condition     = output.inputs.cluster.region == ""
    error_message = "region defaults to empty: a caller that does not know it passes nothing."
  }
  assert {
    condition     = output.inputs.modules.crossplane.enabled == false && output.inputs.modules.crossplane.values == {} && output.inputs.modules.crossplane.values_secret == "" && output.inputs.modules.crossplane.permissions_boundary == ""
    error_message = "crossplane must default to off with no client values and no boundary: no module claims cloud access yet, and the boundary is wired by the root from the foundations."
  }
  assert {
    condition     = output.inputs.modules.external_dns.enabled == false && output.inputs.modules.external_dns.policy == "upsert-only"
    error_message = "external_dns must be off by default — it needs a zone — and upsert-only when enabled: it never deletes a record unless asked."
  }
  assert {
    condition     = output.inputs.modules.external_dns.txt_owner_id == "socle-test" && output.inputs.modules.external_dns.values == {} && output.inputs.modules.external_dns.values_secret == ""
    error_message = "external_dns.txt_owner_id must default to the cluster name, so two clusters never claim each other's records."
  }
  assert {
    condition     = output.inputs.modules.victoria_metrics.enabled == true && output.inputs.modules.victoria_metrics.retention == "15d" && output.inputs.modules.victoria_metrics.storage_size == "20Gi"
    error_message = "victoria_metrics must default to on, 15 days of retention on a 20Gi claim (docs/architecture/observability.md#where-the-data-lives)."
  }
  assert {
    condition     = output.inputs.modules.victoria_metrics.values == {} && output.inputs.modules.victoria_metrics.values_secret == ""
    error_message = "victoria_metrics must default to no client values and no values Secret."
  }
  assert {
    condition     = output.inputs.modules.otel_agent.enabled == true && output.inputs.modules.otel_agent.values == {} && output.inputs.modules.otel_agent.values_secret == ""
    error_message = "otel_agent must default to on, with no client values and no values Secret (docs/reference/inputs.md#the-catalog-schema)."
  }
  assert {
    condition     = output.inputs.modules.otel_gateway.enabled == true && output.inputs.modules.otel_gateway.values == {} && output.inputs.modules.otel_gateway.values_secret == ""
    error_message = "otel_gateway must default to on, with no client values and no values Secret (docs/reference/inputs.md#the-catalog-schema)."
  }
  assert {
    condition     = output.inputs.modules.grafana.enabled == true && output.inputs.modules.grafana.domain == "" && output.inputs.modules.grafana.values == {} && output.inputs.modules.grafana.values_secret == ""
    error_message = "grafana must default to on, with no domain, no client values and no values Secret (docs/reference/inputs.md#the-catalog-schema)."
  }
  assert {
    condition     = output.inputs.modules.victoria_logs.enabled == true && output.inputs.modules.victoria_logs.retention == "7d" && output.inputs.modules.victoria_logs.storage_size == "20Gi"
    error_message = "victoria_logs must default to on, 7 days of retention on a 20Gi claim (docs/architecture/observability.md#where-the-data-lives)."
  }
  assert {
    condition     = output.inputs.modules.otel_agent.logs == true
    error_message = "otel_agent must collect container logs by default, for victoria_logs to store."
  }
  assert {
    condition     = output.inputs.modules.metrics_server.enabled == true && output.inputs.modules.metrics_server.ha == false && output.inputs.modules.metrics_server.values == {} && output.inputs.modules.metrics_server.values_secret == ""
    error_message = "metrics_server must default to on, one replica, no client values: without it every HPA on CPU or memory stays blind, and it needs no client input."
  }
  assert {
    condition     = output.inputs.modules.victoria_traces.enabled == false && output.inputs.modules.victoria_traces.retention == "7d" && output.inputs.modules.victoria_traces.storage_size == "10Gi"
    error_message = "victoria_traces must default to OFF (pre-GA, docs/catalog/victoria-traces.md), 7 days on a 10Gi claim when turned on."
  }
  assert {
    condition     = output.inputs.modules.alerting.enabled == false && output.inputs.modules.alerting.watchdog == true && length(output.inputs.modules.alerting.receivers) == 0 && output.inputs.modules.alerting.receivers_secret == ""
    error_message = "alerting must default to OFF (it needs where alerts go, which only the client knows), the watchdog on when it is turned on."
  }
  assert {
    condition     = output.inputs.modules.kyverno.enabled == false && output.inputs.modules.kyverno_policies.enabled == false
    error_message = "kyverno and kyverno_policies must default to OFF: an admission webhook is opted into (docs/catalog/kyverno.md)."
  }
  assert {
    condition     = output.inputs.modules.kyverno_policies.profile == "baseline" && length(output.inputs.modules.kyverno_policies.enforce) == 0 && length(output.inputs.modules.kyverno_policies.allowed_registries) == 0
    error_message = "kyverno_policies must default to the baseline profile, every policy in Audit, no registry allow-list."
  }
  assert {
    condition     = output.inputs.modules.external_secrets.enabled == false && output.inputs.modules.external_secrets.prefixes == ["socle-test"] && output.inputs.modules.external_secrets.values == {} && output.inputs.modules.external_secrets.values_secret == ""
    error_message = "external_secrets must default to OFF, with the cluster name as its one prefix: the role it declares when turned on reads only secrets under <cluster>/."
  }
  assert {
    condition     = output.inputs.modules.reloader.enabled == false && output.inputs.modules.reloader.values == {} && output.inputs.modules.reloader.values_secret == ""
    error_message = "reloader must default to OFF: it reads every ConfigMap and Secret of the cluster, a grant the client chooses (docs/catalog/reloader.md)."
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

run "crossplane_turns_on_and_its_values_flow_through_untouched" {
  command = plan
  variables {
    kube = {
      crossplane = {
        enabled              = true
        values_secret        = "crossplane-values"
        permissions_boundary = "arn:aws:iam::123456789012:policy/socle/socle-test/socle-test-crossplane-boundary"
        values = {
          metrics                = { enabled = true }
          resourcesCrossplane    = { requests = { memory = "256Mi" } }
          extraObjects           = [{ apiVersion = "v1", kind = "ConfigMap", metadata = { name = "x" } }]
          extraEnvVarsCrossplane = { HTTPS_PROXY = "http://proxy.acme.example:3128" }
        }
      }
    }
  }

  assert {
    condition     = output.inputs.modules.crossplane.enabled == true
    error_message = "enabled=true must reach the inputs."
  }
  assert {
    condition     = output.inputs.modules.crossplane.values.resourcesCrossplane.requests.memory == "256Mi" && output.inputs.modules.crossplane.values.metrics.enabled == true && output.inputs.modules.crossplane.values.extraEnvVarsCrossplane.HTTPS_PROXY == "http://proxy.acme.example:3128"
    error_message = "the client's chart values must reach the inputs as written: the template hands them to helm-controller, nothing rewrites them."
  }
  assert {
    condition     = output.inputs.modules.crossplane.permissions_boundary == "arn:aws:iam::123456789012:policy/socle/socle-test/socle-test-crossplane-boundary"
    error_message = "the permissions boundary the root wires must reach the inputs."
  }
  assert {
    condition     = output.inputs.modules.crossplane.values_secret == "crossplane-values"
    error_message = "the name of the client's values Secret must flow to the inputs."
  }
}

run "the_region_reaches_the_catalog" {
  command = plan
  variables { region = "eu-west-3" }

  assert {
    condition     = output.inputs.cluster.region == "eu-west-3"
    error_message = "the region must reach inputs.cluster.region: the crossplane module's Pod Identity associations are regional."
  }
}

run "external_dns_enabled_with_every_required_value_passes_and_keeps_the_defaults" {
  command = plan
  variables {
    kube = {
      external_dns = {
        enabled        = true
        domain_filters = ["acme.example", "internal.acme.example."]
      }
    }
  }

  assert {
    condition     = output.inputs.modules.external_dns.enabled == true && length(output.inputs.modules.external_dns.domain_filters) == 2
    error_message = "the client's zones must reach the inputs as written."
  }
  assert {
    condition     = output.inputs.modules.external_dns.policy == "upsert-only" && output.inputs.modules.external_dns.txt_owner_id == "socle-test"
    error_message = "attributes the client did not set must keep the catalog defaults, the cluster name included."
  }
}

run "external_dns_with_crossplane_on_aws_passes_with_the_region" {
  command = plan
  variables {
    region = "eu-west-3"
    kube = {
      crossplane   = { enabled = true }
      external_dns = { enabled = true, domain_filters = ["acme.example"] }
    }
  }

  assert {
    condition     = output.inputs.cluster.region == "eu-west-3" && output.inputs.modules.crossplane.enabled && output.inputs.modules.external_dns.enabled
    error_message = "the region and both modules must reach the inputs: the template builds the module's association from them."
  }
}

run "external_dns_values_pass_through_and_a_credential_by_reference_is_allowed" {
  command = plan
  variables {
    kube = {
      external_dns = {
        values = {
          logLevel  = "debug"
          extraArgs = { aws-zone-type = "public" }
          env = [{
            name      = "AWS_SECRET_ACCESS_KEY"
            valueFrom = { secretKeyRef = { name = "mine", key = "k" } }
          }]
        }
        values_secret = "external-dns-private-values"
      }
    }
  }

  assert {
    condition     = output.inputs.modules.external_dns.values.logLevel == "debug" && output.inputs.modules.external_dns.values_secret == "external-dns-private-values"
    error_message = "values and values_secret must reach the inputs as written."
  }
  assert {
    condition     = output.inputs.modules.external_dns.policy == "upsert-only"
    error_message = "setting values must leave the named attributes at their defaults."
  }
}

run "keda_is_off_by_default_with_no_cloud_role" {
  command = plan

  assert {
    condition     = output.inputs.modules.keda.enabled == false && output.inputs.modules.keda.services == [] && output.inputs.modules.keda.values == {} && output.inputs.modules.keda.values_secret == ""
    error_message = "keda must default to off — it does nothing until a ScaledObject exists — with no service named: the operator gets a cloud role only for the services the client lists."
  }
}

run "keda_with_named_services_and_crossplane_on_aws_passes_with_the_region" {
  command = plan
  variables {
    region = "eu-west-3"
    kube = {
      crossplane = { enabled = true }
      keda       = { enabled = true, services = ["sqs", "cloudwatch"] }
    }
  }

  assert {
    condition     = output.inputs.modules.keda.enabled && output.inputs.modules.keda.services == ["sqs", "cloudwatch"] && output.inputs.cluster.region == "eu-west-3"
    error_message = "the services, the module and the region must reach the inputs as written: the template builds one read-only statement per service from them."
  }
}

run "keda_on_without_a_service_needs_neither_crossplane_nor_a_region" {
  command = plan
  variables {
    kube = { keda = { enabled = true } }
  }

  assert {
    condition     = output.inputs.modules.keda.enabled && length(output.inputs.modules.keda.services) == 0
    error_message = "KEDA with cron, Prometheus or credential-based triggers needs no cloud role: on with an empty list must plan without Crossplane."
  }
}

run "keda_values_pass_through_and_a_credential_by_reference_is_allowed" {
  command = plan
  variables {
    kube = {
      keda = {
        values = {
          resources = { operator = { requests = { memory = "160Mi" } } }
          operator = { env = [{
            name      = "AWS_SECRET_ACCESS_KEY"
            valueFrom = { secretKeyRef = { name = "mine", key = "k" } }
          }] }
        }
        values_secret = "keda-values"
      }
    }
  }

  assert {
    condition     = output.inputs.modules.keda.values.resources.operator.requests.memory == "160Mi" && output.inputs.modules.keda.values_secret == "keda-values"
    error_message = "values and values_secret must reach the inputs as written."
  }
}

run "scaleway_is_a_plain_kubernetes_cluster_for_the_operator" {
  command = plan
  variables {
    cloud           = "scaleway"
    cluster_network = null
  }

  assert {
    condition     = yamldecode(helm_release.instance.values[0]).instance.cluster.type == "kubernetes"
    error_message = "Scaleway has no workload identity federation the operator knows; cluster.type must be kubernetes."
  }
  assert {
    condition     = output.inputs.cloud == "scaleway"
    error_message = "inputs.cloud must carry the socle's own cloud name, which the artifact's clusters/<cloud> path uses."
  }
  assert {
    condition     = length(helm_release.cilium) == 0 && length(helm_release.coredns) == 0 && output.inputs.cilium.installed == false
    error_message = "Kapsule operates Cilium: the socle must install nothing on scaleway, and the templates must be told so."
  }
  assert {
    condition     = length(aws_eks_addon.pod_identity_agent) == 0 && length(aws_eks_addon.ebs_csi) == 0 && length(aws_eks_addon.efs_csi) == 0 && length(aws_iam_role.ebs_csi) == 0
    error_message = "EKS add-ons exist only on aws: nothing of eks_addons.tf may be planned elsewhere, whatever its defaults."
  }
}

# --- Cilium — cilium.tf, docs/architecture/cilium-before-flux.md ---

run "aws_installs_cilium_and_coredns_before_flux" {
  command = plan

  assert {
    condition     = length(helm_release.cilium) == 1 && length(helm_release.coredns) == 1
    error_message = "on aws the foundations create a cluster with no CNI, kube-proxy or CoreDNS: both releases must exist by default."
  }
  assert {
    condition     = yamldecode(helm_release.cilium[0].values[0]).gatewayAPI.gatewayClass.create == "false"
    error_message = "the cilium GatewayClass belongs to the gateway_api catalog module: the chart's auto would render it into this release once the CRDs exist, and two owners would fight over it."
  }
  assert {
    condition     = yamldecode(helm_release.cilium[0].values[0]).eni.enabled == true
    error_message = "aws must run Cilium in ENI mode: pods carry VPC addresses, as the foundations' network design assumes."
  }
  assert {
    condition     = yamldecode(helm_release.cilium[0].values[0]).kubeProxyReplacement == true && yamldecode(helm_release.cilium[0].values[0]).k8sServiceHost == "ABCDEF.gr7.eu-west-3.eks.amazonaws.com" && yamldecode(helm_release.cilium[0].values[0]).k8sServicePort == 443
    error_message = "with no kube-proxy, Cilium must replace it and reach the API server by the host the foundations output, port 443."
  }
  assert {
    condition     = yamldecode(helm_release.cilium[0].values[0]).operator.replicas == 1 && yamldecode(helm_release.cilium[0].values[0]).hubble.relay.enabled == false && yamldecode(helm_release.cilium[0].values[0]).hubble.ui.enabled == false && yamldecode(helm_release.cilium[0].values[0]).gatewayAPI.enabled == true
    error_message = "the defaults are one operator, no Hubble Relay/UI, and Cilium serving the Gateway API."
  }
  assert {
    condition     = yamldecode(helm_release.coredns[0].values[0]).service.clusterIP == "172.20.0.10" && yamldecode(helm_release.coredns[0].values[0]).service.name == "kube-dns"
    error_message = "CoreDNS must take the .10 address of the service range under the kube-dns name — what every EKS node's kubelet is told to use."
  }
  assert {
    condition     = output.inputs.cilium.installed == true && output.inputs.cilium.gatewayApi == true && output.inputs.cilium.hubble == false
    error_message = "the templates must be told that the socle's Cilium runs here and serves the Gateway API."
  }
  assert {
    condition     = output.cilium.chart_version == "1.20.2" && output.cilium.coredns_version == "1.47.1"
    error_message = "the pinned versions must be visible to the root that consumes them."
  }
}

run "azure_installs_cilium_in_byocni_mode_and_no_coredns" {
  command = plan
  variables {
    cloud = "azure"
    cluster_network = {
      api_endpoint = "socle-test-abc123.privatelink.westeurope.azmk8s.io"
      pod_cidr     = "10.244.0.0/16"
    }
  }

  assert {
    condition     = length(helm_release.cilium) == 1 && length(helm_release.coredns) == 0
    error_message = "AKS ships CoreDNS as a system pod even under BYO CNI: Cilium only."
  }
  assert {
    condition     = yamldecode(helm_release.cilium[0].values[0]).aksbyocni.enabled == true && !can(yamldecode(helm_release.cilium[0].values[0]).eni)
    error_message = "azure must run Cilium in AKS BYOCNI mode, and carry nothing of the aws configuration."
  }
  assert {
    condition     = yamldecode(helm_release.cilium[0].values[0]).ipam.operator.clusterPoolIPv4PodCIDRList == ["10.244.0.0/16"]
    error_message = "the cluster pool must be the foundations' pod_cidr: the chart's default, 10.0.0.0/8, contains the VNet."
  }
  assert {
    condition     = yamldecode(helm_release.cilium[0].values[0]).k8sServiceHost == "socle-test-abc123.privatelink.westeurope.azmk8s.io" && yamldecode(helm_release.cilium[0].values[0]).k8sServicePort == 443
    error_message = "a bare FQDN, as AKS outputs it, must become the API server host with port 443."
  }
}

run "gcp_operates_its_own_cilium" {
  command = plan
  variables {
    cloud           = "gcp"
    cluster_network = null
  }

  assert {
    condition     = length(helm_release.cilium) == 0 && length(helm_release.coredns) == 0
    error_message = "Autopilot's Dataplane V2 is Cilium: the socle must install nothing on gcp."
  }
  assert {
    condition     = output.inputs.cilium.installed == false && output.inputs.cilium.gatewayApi == false && output.cilium.chart_version == null
    error_message = "the templates and the root must be told that no socle-managed Cilium exists here."
  }
}

run "a_cluster_that_brings_its_own_cni_turns_cilium_off" {
  command = plan
  variables {
    cilium          = { enabled = false }
    cluster_network = null
  }

  assert {
    condition     = length(helm_release.cilium) == 0 && length(helm_release.coredns) == 0
    error_message = "cilium.enabled = false must install neither release: the cluster brings its own CNI and DNS — floci's k3s in the e2e jobs."
  }
  assert {
    condition     = output.inputs.cilium.installed == false
    error_message = "the templates must not assume the Gateway API CRDs or a cilium GatewayClass on a cluster that brought its own CNI."
  }
}

run "hubble_and_gateway_api_toggles_reach_the_chart_and_the_templates" {
  command = plan
  variables {
    cilium = { hubble = true, gateway_api = false }
  }

  assert {
    condition     = yamldecode(helm_release.cilium[0].values[0]).hubble.relay.enabled == true && yamldecode(helm_release.cilium[0].values[0]).hubble.ui.enabled == true
    error_message = "hubble = true must enable Relay and UI together."
  }
  assert {
    condition     = yamldecode(helm_release.cilium[0].values[0]).gatewayAPI.enabled == false
    error_message = "gateway_api = false turns Cilium's Gateway API controller off."
  }
  assert {
    condition     = output.inputs.cilium.hubble == true && output.inputs.cilium.gatewayApi == false
    error_message = "the templates must see the toggles as set."
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

run "client_values_are_merged_after_the_socles_so_the_client_wins" {
  command = plan
  variables {
    cilium = { values = {
      operator         = { replicas = 2 }
      bandwidthManager = { enabled = true }
      # A Secret named, not inlined: what the refusal points the client to.
      hubble = { tls = { server = { existingSecret = "hubble-server-certs" } } }
    } }
    coredns = { values = { replicaCount = 3 } }
  }

  assert {
    condition     = length(helm_release.cilium[0].values) == 2 && yamldecode(helm_release.cilium[0].values[0]).operator.replicas == 1 && yamldecode(helm_release.cilium[0].values[1]).operator.replicas == 2
    error_message = "Cilium's values must be the socle's block then the client's: the helm provider merges the list in order, so the client's operator.replicas wins and the socle's block stays readable."
  }
  assert {
    condition     = yamldecode(helm_release.cilium[0].values[1]).bandwidthManager.enabled == true
    error_message = "any Cilium chart value must reach the release, not only the attributes the socle exposes."
  }
  assert {
    condition     = yamldecode(helm_release.cilium[0].values[1]).hubble.tls.server.existingSecret == "hubble-server-certs"
    error_message = "naming an existing Secret must be accepted: it is the way secrets reach Cilium without entering the state."
  }
  assert {
    condition     = length(helm_release.coredns[0].values) == 2 && yamldecode(helm_release.coredns[0].values[0]).replicaCount == 2 && yamldecode(helm_release.coredns[0].values[1]).replicaCount == 3
    error_message = "CoreDNS's values must be the socle's block then the client's, the client's winning."
  }
}

run "no_client_values_is_an_empty_last_layer" {
  command = plan

  assert {
    condition     = yamldecode(helm_release.cilium[0].values[1]) == {} && yamldecode(helm_release.coredns[0].values[1]) == {}
    error_message = "absent client values must merge as an empty map, changing nothing."
  }
}

run "every_cloud_names_the_gateway_class_templates_target" {
  command = plan

  assert {
    condition     = output.inputs.gateway.className == "cilium"
    error_message = "on aws the socle's Cilium serves Gateway API: templates target the cilium class."
  }
}

run "gcp_targets_gkes_managed_gateway_class" {
  command = plan
  variables {
    cloud           = "gcp"
    cluster_network = null
  }

  assert {
    condition     = output.inputs.gateway.className == "gke-l7-global-external-managed"
    error_message = "on gcp GKE's controller serves Gateway API (gateway_api_config in opentofu/gcp): templates target its global external managed class."
  }
}

run "no_gateway_class_where_nothing_implements_gateway_api" {
  command = plan
  variables {
    cilium = { gateway_api = false }
  }

  assert {
    condition     = output.inputs.gateway.className == ""
    error_message = "with Cilium's Gateway API off, no class exists: templates must be told so, and render no Gateway."
  }
}

run "gateway_api_is_a_catalog_module_on_by_default" {
  command = plan

  assert {
    condition     = output.inputs.modules.gateway_api.enabled == true
    error_message = "Gateway API is installed by default for every client: the module is on unless the client turns it off."
  }
}

run "a_cluster_with_no_node_fails_at_plan_not_after_a_helm_timeout" {
  command = plan
  variables {
    schedulable_nodes = 0
  }

  expect_failures = [helm_release.coredns, aws_eks_addon.pod_identity_agent]
}

run "with_no_coredns_to_install_the_flux_operator_carries_the_check" {
  command = plan
  variables {
    cloud             = "azure"
    schedulable_nodes = 0
  }

  expect_failures = [helm_release.operator]
}

run "a_cluster_with_nodes_plans_cilium_coredns_and_flux" {
  command = plan
  variables {
    schedulable_nodes = 2
  }

  assert {
    condition     = length(helm_release.cilium) == 1 && length(helm_release.coredns) == 1 && helm_release.operator.name == "flux-operator"
    error_message = "with nodes to schedule on, the releases that need one must plan as usual."
  }
}

run "argocd_accepts_a_domain_and_the_ha_switch" {
  command = plan
  variables {
    kube = { argocd = { domain = "argocd.acme.example", ha = true } }
  }

  assert {
    condition     = output.inputs.modules.argocd.domain == "argocd.acme.example" && output.inputs.modules.argocd.ha == true
    error_message = "a valid domain and ha=true must reach the inputs as set."
  }
  assert {
    condition     = output.inputs.modules.argocd.enabled == true && output.inputs.modules.argocd.admin_enabled == true
    error_message = "attributes the client did not set must keep the catalog default."
  }
}

run "argocd_values_flow_through_untouched_and_a_repository_without_credentials_is_fine" {
  command = plan
  variables {
    kube = {
      argocd = {
        values_secret = "argocd-values"
        values = {
          configs = {
            cm   = { "accounts.alice" = "apiKey, login" }
            rbac = { "policy.csv" = "g, platform, role:admin" }
            repositories = {
              app = { url = "https://github.com/acme/app", type = "git" }
            }
          }
        }
      }
    }
  }

  assert {
    condition     = output.inputs.modules.argocd.values.configs.rbac["policy.csv"] == "g, platform, role:admin" && output.inputs.modules.argocd.values.configs.repositories.app.url == "https://github.com/acme/app"
    error_message = "the client's chart values must reach the inputs as written: the template hands them to helm-controller, nothing rewrites them."
  }
  assert {
    condition     = output.inputs.modules.argocd.values_secret == "argocd-values"
    error_message = "the name of the client's values Secret must flow to the inputs."
  }
}

run "victoria_metrics_accepts_no_volume_and_a_retention_in_hours" {
  command = plan
  variables {
    kube = { victoria_metrics = { storage_size = "", retention = "48h" } }
  }

  assert {
    condition     = output.inputs.modules.victoria_metrics.storage_size == "" && output.inputs.modules.victoria_metrics.retention == "48h"
    error_message = "an empty storage_size (the emptyDir escape) and a retention of at least a day in hours must reach the inputs as set."
  }
  assert {
    condition     = output.inputs.modules.victoria_metrics.enabled == true
    error_message = "attributes the client did not set must keep the catalog default."
  }
}

run "victoria_metrics_values_flow_through_and_a_credential_from_a_secret_ref_is_fine" {
  command = plan
  variables {
    kube = {
      victoria_metrics = {
        storage_size  = "1Ti"
        values_secret = "victoria-metrics-values"
        values = {
          server = {
            extraArgs = { "storage.maxHourlySeries" = "50000" }
            env = [{
              name      = "VM_httpAuth_password"
              valueFrom = { secretKeyRef = { name = "vm-auth", key = "password" } }
            }]
          }
        }
      }
    }
  }

  assert {
    condition     = output.inputs.modules.victoria_metrics.values.server.extraArgs["storage.maxHourlySeries"] == "50000" && output.inputs.modules.victoria_metrics.values.server.env[0].valueFrom.secretKeyRef.name == "vm-auth"
    error_message = "the client's chart values must reach the inputs as written, a credential read from a Secret included: only a literal value is refused."
  }
  assert {
    condition     = output.inputs.modules.victoria_metrics.values_secret == "victoria-metrics-values" && output.inputs.modules.victoria_metrics.storage_size == "1Ti"
    error_message = "the values Secret's name and a size in Ti must flow to the inputs."
  }
}

run "otel_agent_values_flow_through_and_credentials_read_from_the_environment_are_fine" {
  command = plan
  variables {
    kube = {
      otel_agent = {
        values_secret = "otel-agent-values"
        values = {
          extraEnvs = [{
            name      = "SAAS_TOKEN"
            valueFrom = { secretKeyRef = { name = "saas", key = "token" } }
          }]
          config = {
            extensions = { bearertokenauth = { token = "$${env:SAAS_TOKEN}" } }
            exporters = {
              "otlp_http/saas" = { endpoint = "https://otlp.example", headers = { Authorization = "Bearer $${env:SAAS_TOKEN}" } }
            }
          }
        }
      }
    }
  }

  assert {
    condition     = output.inputs.modules.otel_agent.values.config.extensions.bearertokenauth.token == "$${env:SAAS_TOKEN}" && output.inputs.modules.otel_agent.values.extraEnvs[0].valueFrom.secretKeyRef.name == "saas"
    error_message = "a credential the collector reads from its environment, set from a Secret, must reach the inputs as written: only a literal is refused."
  }
  assert {
    condition     = output.inputs.modules.otel_agent.values_secret == "otel-agent-values"
    error_message = "the name of the client's values Secret must flow to the inputs."
  }
}

# --- EKS-managed add-ons — eks_addons.tf, docs/decisions/aws.md ---

run "aws_installs_the_pod_identity_agent_and_ebs_csi_by_default" {
  command = plan

  assert {
    condition     = aws_eks_addon.pod_identity_agent[0].addon_name == "eks-pod-identity-agent" && aws_eks_addon.pod_identity_agent[0].cluster_name == "socle-test"
    error_message = "the Pod Identity Agent must be installed on the cluster by default: without it every Pod Identity association, Crossplane's included, hangs without an error (#48)."
  }
  assert {
    condition     = aws_eks_addon.ebs_csi[0].addon_name == "aws-ebs-csi-driver" && length(aws_eks_addon.efs_csi) == 0 && length(aws_iam_role.efs_csi) == 0
    error_message = "EBS CSI is delegated to EKS and on by default; EFS CSI is a catalog option, off by default, with no role."
  }
  assert {
    condition     = alltrue([for a in [aws_eks_addon.pod_identity_agent[0], aws_eks_addon.ebs_csi[0]] : can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+-eksbuild\\.[0-9]+$", a.addon_version))])
    error_message = "every add-on version must be pinned to one exact eksbuild, never left to AWS's default or most_recent."
  }
  assert {
    condition     = output.eks_addons.pod_identity_agent.version == aws_eks_addon.pod_identity_agent[0].addon_version && output.eks_addons.ebs_csi.version == aws_eks_addon.ebs_csi[0].addon_version && output.eks_addons.efs_csi == null
    error_message = "the pinned versions must be visible to the root that consumes them, and an add-on not installed must be null."
  }
}

run "the_ebs_csi_controller_runs_as_its_own_role_through_pod_identity" {
  command = plan

  assert {
    condition     = one(aws_eks_addon.ebs_csi[0].pod_identity_association).service_account == "ebs-csi-controller-sa"
    error_message = "the EBS CSI controller's identity must be bound through the add-on's own pod_identity_association, on the controller's ServiceAccount."
  }
  assert {
    condition     = aws_iam_role_policy_attachment.ebs_csi[0].policy_arn == "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
    error_message = "the EBS CSI role must carry AWS's managed driver policy, and nothing else."
  }
  assert {
    condition     = aws_iam_role.ebs_csi[0].name == "socle-test-ebs-csi" && aws_iam_role.ebs_csi[0].path == "/"
    error_message = "the EBS CSI role must be named after the cluster and live outside /socle/<cluster>/, the path Crossplane may rewrite."
  }
  assert {
    condition     = jsondecode(aws_iam_role.ebs_csi[0].assume_role_policy).Statement[0].Principal.Service == "pods.eks.amazonaws.com" && contains(jsondecode(aws_iam_role.ebs_csi[0].assume_role_policy).Statement[0].Action, "sts:TagSession")
    error_message = "the EBS CSI role must be trusted by EKS Pod Identity, not IRSA."
  }
}

run "efs_csi_is_installed_on_request_with_its_own_role" {
  command = plan
  variables {
    eks_addons = { efs_csi = true }
  }

  assert {
    condition     = aws_eks_addon.efs_csi[0].addon_name == "aws-efs-csi-driver" && one(aws_eks_addon.efs_csi[0].pod_identity_association).service_account == "efs-csi-controller-sa"
    error_message = "efs_csi = true must install the EFS CSI add-on, its controller bound to its own role through Pod Identity."
  }
  assert {
    condition     = aws_iam_role.efs_csi[0].name == "socle-test-efs-csi" && aws_iam_role_policy_attachment.efs_csi[0].policy_arn == "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
    error_message = "the EFS CSI role must be named after the cluster and carry AWS's managed driver policy."
  }
  assert {
    condition     = length(aws_eks_addon.pod_identity_agent) == 1 && length(aws_eks_addon.ebs_csi) == 1
    error_message = "turning one add-on on must leave the others at their defaults."
  }
}

run "every_eks_addon_can_be_turned_off" {
  command = plan
  variables {
    eks_addons = { pod_identity_agent = false, ebs_csi = false, snapshot_controller = false }
  }

  assert {
    condition     = length(aws_eks_addon.pod_identity_agent) == 0 && length(aws_eks_addon.ebs_csi) == 0 && length(aws_iam_role.ebs_csi) == 0 && length(aws_eks_addon.efs_csi) == 0 && length(aws_eks_addon.snapshot_controller) == 0
    error_message = "a cluster that brings its own — the e2e test double — must be able to turn every add-on off, and the roles go with them."
  }
  assert {
    condition     = output.eks_addons.pod_identity_agent == null && output.eks_addons.ebs_csi == null && output.eks_addons.snapshot_controller == null && output.inputs.storage.snapshots == false
    error_message = "an add-on not installed must be null in the output, and the templates told there are no snapshots."
  }
}

# --- The shared Gateways — docs/catalog/gateway-api.md ---

run "no_shared_gateway_on_aws_without_a_certificate" {
  command = plan

  assert {
    condition     = output.inputs.gateway.shared == false && output.inputs.gateway.certificateArn == ""
    error_message = "on aws TLS terminates at the load balancer: without the foundations' certificate no Gateway may be created, never one serving clear text."
  }
  assert {
    condition     = output.inputs.modules.gateway_api.gateways == true && output.inputs.modules.argocd.gateway == "private"
    error_message = "the shared Gateways are on by default, and ArgoCD's route targets the private one."
  }
}

run "aws_with_a_certificate_gets_the_shared_gateways" {
  command = plan
  variables {
    gateway_certificate_arn = "arn:aws:acm:eu-west-3:000000000000:certificate/00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = output.inputs.gateway.shared == true && output.inputs.gateway.namespace == "gateway-system" && output.inputs.gateway.className == "cilium"
    error_message = "with the certificate, the templates must be told to create the shared Gateways in gateway-system, on the cilium class."
  }
  assert {
    condition     = output.inputs.gateway.certificateArn == "arn:aws:acm:eu-west-3:000000000000:certificate/00000000-0000-0000-0000-000000000000"
    error_message = "the certificate ARN must reach the templates untouched: the NLBs terminate TLS with it."
  }
}

run "the_client_can_keep_the_class_and_drop_the_shared_gateways" {
  command = plan
  variables {
    gateway_certificate_arn = "arn:aws:acm:eu-west-3:000000000000:certificate/00000000-0000-0000-0000-000000000000"
    kube                    = { gateway_api = { gateways = false } }
  }

  assert {
    condition     = output.inputs.gateway.shared == false && output.inputs.gateway.className == "cilium"
    error_message = "gateways = false must drop the shared Gateways and keep the class."
  }
}

run "azure_gets_the_shared_gateways_without_an_aws_certificate" {
  command = plan
  variables {
    cloud = "azure"
  }

  assert {
    condition     = output.inputs.gateway.shared == true && output.inputs.gateway.certificateArn == ""
    error_message = "on azure Envoy terminates TLS with the client's Secret: the shared Gateways need no AWS certificate."
  }
}

run "no_shared_gateway_where_cilium_does_not_serve_gateway_api" {
  command = plan
  variables {
    gateway_certificate_arn = "arn:aws:acm:eu-west-3:000000000000:certificate/00000000-0000-0000-0000-000000000000"
    cilium                  = { enabled = false }
  }

  assert {
    condition     = output.inputs.gateway.shared == false
    error_message = "without the socle's Cilium there is no class to create a Gateway on — the e2e test double's case."
  }
}

run "otel_gateway_values_flow_through_and_a_header_read_from_the_environment_is_fine" {
  command = plan
  variables {
    kube = {
      otel_gateway = {
        values = {
          config = {
            exporters = { "otlp_http/saas" = { endpoint = "https://otlp.example", headers = { "X-API-Key" = "$${env:SAAS_KEY}" } } }
          }
        }
      }
    }
  }

  assert {
    condition     = output.inputs.modules.otel_gateway.values.config.exporters["otlp_http/saas"].headers["X-API-Key"] == "$${env:SAAS_KEY}"
    error_message = "a header the collector reads from its environment must reach the inputs as written: only a literal is refused."
  }
}

run "grafana_accepts_a_domain_and_secrets_grafana_resolves_itself" {
  command = plan
  variables {
    kube = {
      grafana = {
        domain = "grafana.acme.example"
        values = {
          admin        = { existingSecret = "grafana-admin" }
          envValueFrom = { PG_PASSWORD = { secretKeyRef = { name = "pg", key = "password" } } }
          datasources = {
            "extra.yaml" = {
              apiVersion = 1
              datasources = [
                { name = "pg", type = "postgres", secureJsonData = { password = "$${PG_PASSWORD}" } },
                { name = "tls", type = "prometheus", secureJsonData = { tlsClientKey = "$__file{/etc/secrets/tls.key}" } },
              ]
            }
          }
        }
      }
    }
  }

  assert {
    condition     = output.inputs.modules.grafana.domain == "grafana.acme.example" && output.inputs.modules.grafana.values.admin.existingSecret == "grafana-admin"
    error_message = "a valid domain and an admin Secret by name must reach the inputs as set."
  }
  assert {
    condition     = output.inputs.modules.grafana.values.datasources["extra.yaml"].datasources[0].secureJsonData.password == "$${PG_PASSWORD}"
    error_message = "a secureJsonData value Grafana resolves itself ($${VAR}, $__file{…}) must flow through: only a literal is refused."
  }
}

run "victoria_logs_accepts_no_volume_and_otel_agent_without_logs" {
  command = plan
  variables {
    kube = {
      victoria_logs = { storage_size = "", retention = "2w" }
      otel_agent    = { logs = false }
    }
  }

  assert {
    condition     = output.inputs.modules.victoria_logs.storage_size == "" && output.inputs.modules.victoria_logs.retention == "2w" && output.inputs.modules.otel_agent.logs == false
    error_message = "an empty storage_size, a retention in weeks and an agent without logs must reach the inputs as set."
  }
}

run "victoria_traces_turns_on_with_a_retention_in_days" {
  command = plan
  variables {
    kube = { victoria_traces = { enabled = true, retention = "3d" } }
  }

  assert {
    condition     = output.inputs.modules.victoria_traces.enabled == true && output.inputs.modules.victoria_traces.retention == "3d" && output.inputs.modules.victoria_traces.storage_size == "10Gi"
    error_message = "a client turning traces on must get them with his retention and the default claim."
  }
}

run "kyverno_policies_turn_on_with_enforce_and_an_allow_list" {
  command = plan
  variables {
    kube = {
      kyverno = { enabled = true }
      kyverno_policies = {
        enabled            = true
        profile            = "restricted"
        enforce            = ["disallow-privileged-containers", "require-run-as-nonroot", "restrict-image-registries"]
        allowed_registries = ["ghcr.io", "registry.k8s.io", "123456789012.dkr.ecr.eu-west-3.amazonaws.com/acme", "localhost:5000"]
      }
    }
  }

  assert {
    condition     = output.inputs.modules.kyverno.enabled == true && output.inputs.modules.kyverno_policies.profile == "restricted"
    error_message = "a client turning the policies on with the engine must get the profile he chose."
  }
  assert {
    condition     = output.inputs.modules.kyverno_policies.enforce == ["disallow-privileged-containers", "require-run-as-nonroot", "restrict-image-registries"] && length(output.inputs.modules.kyverno_policies.allowed_registries) == 4
    error_message = "enforce and allowed_registries must reach the inputs as set."
  }
}

run "reloader_values_pass_through_and_an_existing_secret_is_allowed" {
  command = plan
  variables {
    kube = {
      reloader = {
        enabled = true
        values = {
          reloader = {
            logFormat  = "json"
            deployment = { env = { existing = { reloader-alerts = { ALERT_WEBHOOK_URL = "url" } } } }
          }
        }
        values_secret = "reloader-values"
      }
    }
  }

  assert {
    condition     = output.inputs.modules.reloader.enabled && output.inputs.modules.reloader.values.reloader.logFormat == "json" && output.inputs.modules.reloader.values_secret == "reloader-values"
    error_message = "values and values_secret must reach the inputs as written; a credential referenced through env.existing is not a literal and must pass."
  }
}

run "external_secrets_with_crossplane_on_aws_passes_with_the_region_and_its_prefixes" {
  command = plan
  variables {
    region = "eu-west-3"
    kube = {
      crossplane       = { enabled = true }
      external_secrets = { enabled = true, prefixes = ["socle-test", "shared/platform"] }
    }
  }

  assert {
    condition     = output.inputs.modules.external_secrets.enabled && output.inputs.modules.external_secrets.prefixes == ["socle-test", "shared/platform"] && output.inputs.cluster.region == "eu-west-3"
    error_message = "the prefixes and the region must reach the inputs as written: the template scopes the role's ARNs from them."
  }
}

run "external_secrets_without_crossplane_needs_no_region" {
  command = plan
  variables {
    kube = { external_secrets = { enabled = true } }
  }

  assert {
    condition     = output.inputs.modules.external_secrets.enabled && output.inputs.modules.crossplane.enabled == false
    error_message = "ESO with Crossplane off installs the operator alone, the client bringing his stores: it must plan without a region."
  }
}

run "external_secrets_with_no_prefix_needs_no_region" {
  command = plan
  variables {
    kube = {
      crossplane       = { enabled = true }
      external_secrets = { enabled = true, prefixes = [] }
    }
  }

  assert {
    condition     = length(output.inputs.modules.external_secrets.prefixes) == 0
    error_message = "an empty prefixes list means no role and no store: it must plan without a region."
  }
}

run "external_secrets_values_pass_through_and_an_endpoint_is_not_a_credential" {
  command = plan
  variables {
    kube = {
      external_secrets = {
        values = {
          log      = { level = "debug" }
          extraEnv = [{ name = "AWS_SECRETSMANAGER_ENDPOINT", value = "http://localhost:4566" }]
        }
        values_secret = "external-secrets-values"
      }
    }
  }

  assert {
    condition     = output.inputs.modules.external_secrets.values.log.level == "debug" && output.inputs.modules.external_secrets.values_secret == "external-secrets-values"
    error_message = "values and values_secret must reach the inputs as written; AWS_SECRETSMANAGER_ENDPOINT names an endpoint, not a credential."
  }
}

# --- velero — docs/catalog/velero.md ---

run "velero_is_off_by_default_with_the_seven_policies" {
  command = plan

  assert {
    condition     = output.inputs.modules.velero.enabled == false && output.inputs.modules.velero.node_agent == false && output.inputs.modules.velero.values_secret == ""
    error_message = "velero must be off by default — it needs Crossplane — and without the node-agent while the EFS driver is off: no privileged DaemonSet for nothing."
  }
  assert {
    condition = [for p in output.inputs.modules.velero.policies : "${p.frequency}-${p.retention}"] == [
      "hourly-24h", "hourly-48h", "daily-7d", "daily-30d", "weekly-30d", "weekly-90d", "monthly-90d",
    ]
    error_message = "the seven default pairs are the menu every application chooses from (docs/catalog/velero.md §3)."
  }
  assert {
    condition     = one([for p in output.inputs.modules.velero.policies : p.schedule if p.frequency == "monthly"]) == "0 3 1 * *"
    error_message = "the monthly pair runs at 03:00 on the first, an hour after the daily ones."
  }
}

run "the_cluster_account_and_the_snapshot_controller_reach_the_inputs_on_aws" {
  command = plan

  assert {
    condition     = output.inputs.cluster.accountId == "000000000000" && output.inputs.storage.snapshots == true
    error_message = "on aws the account (the bucket's name carries it) and the snapshot controller's presence must reach the templates."
  }
  assert {
    condition     = aws_eks_addon.snapshot_controller[0].addon_name == "snapshot-controller" && can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+-eksbuild\\.[0-9]+$", aws_eks_addon.snapshot_controller[0].addon_version)) && output.eks_addons.snapshot_controller.version == aws_eks_addon.snapshot_controller[0].addon_version
    error_message = "the snapshot controller is an EKS add-on, pinned, on by default."
  }
}

run "no_account_and_no_snapshots_off_aws" {
  command = plan
  variables {
    cloud           = "gcp"
    cluster_network = null
  }

  assert {
    condition     = output.inputs.cluster.accountId == "" && output.inputs.storage.snapshots == false && length(aws_eks_addon.snapshot_controller) == 0
    error_message = "elsewhere there is no AWS account to read and no EKS add-on."
  }
}

run "velero_turns_on_with_crossplane_its_own_policies_and_the_node_agent" {
  command = plan
  variables {
    region = "eu-west-3"
    kube = {
      crossplane = { enabled = true }
      velero = {
        enabled    = true
        node_agent = true
        policies   = [{ frequency = "daily", retention = "14d", schedule = "15 1 * * *" }]
        values     = { credentials = { useSecret = true, existingSecret = "velero-keys" } }
      }
    }
  }

  assert {
    condition     = output.inputs.modules.velero.enabled && output.inputs.modules.velero.node_agent && length(output.inputs.modules.velero.policies) == 1 && output.inputs.modules.velero.policies[0].retention == "14d"
    error_message = "the client's list replaces the seven pairs, and the node-agent switch reaches the inputs."
  }
  assert {
    condition     = output.inputs.modules.velero.values.credentials.existingSecret == "velero-keys"
    error_message = "naming a Secret the client created is not a secret: it must pass."
  }
}

run "velero_runs_the_node_agent_by_default_when_the_efs_driver_is_on" {
  command = plan
  variables {
    eks_addons = { efs_csi = true }
  }

  assert {
    condition     = output.inputs.modules.velero.node_agent == true
    error_message = "EFS has no CSI snapshots: with its driver on, the node-agent is what backs its volumes up."
  }
}

run "metrics_server_values_flow_through_untouched_and_honest_kubelet_flags_are_allowed" {
  command = plan
  variables {
    kube = {
      metrics_server = {
        ha            = true
        values_secret = "metrics-server-values"
        values = {
          # A real flag that starts like the refused one: the check matches
          # the flag's whole name, not a prefix.
          args = ["--v=2", "--kubelet-preferred-address-types=InternalIP"]
        }
      }
    }
  }

  assert {
    condition     = output.inputs.modules.metrics_server.ha == true && output.inputs.modules.metrics_server.enabled == true
    error_message = "ha=true must reach the inputs as set, and enabled keep its default."
  }
  assert {
    condition     = output.inputs.modules.metrics_server.values.args == ["--v=2", "--kubelet-preferred-address-types=InternalIP"]
    error_message = "the client's chart values must reach the inputs as written, an honest --kubelet-* flag included."
  }
  assert {
    condition     = output.inputs.modules.metrics_server.values_secret == "metrics-server-values"
    error_message = "the name of the client's values Secret must flow to the inputs."
  }
}

run "alerting_turns_on_with_receivers_a_route_and_the_watchdog" {
  command = plan
  variables {
    kube = {
      alerting = {
        enabled          = true
        receivers_secret = "alerting-keys"
        receivers = [
          { name = "team", slack_configs = [{ api_url_file = "/etc/alertmanager/secrets/slack-url", channel = "#alerts" }] },
          { name = "on-call", pagerduty_configs = [{ routing_key_file = "/etc/alertmanager/secrets/pagerduty-key" }] },
        ]
        route  = { receiver = "team", routes = [{ receiver = "on-call", matchers = ["severity=\"critical\""] }] }
        values = { server = { resources = { requests = { memory = "96Mi" } } } }
      }
    }
  }

  assert {
    condition     = output.inputs.modules.alerting.enabled && output.inputs.modules.alerting.watchdog && output.inputs.modules.alerting.receivers_secret == "alerting-keys"
    error_message = "enabled, the watchdog's default and receivers_secret must reach the inputs."
  }
  assert {
    condition     = length(output.inputs.modules.alerting.receivers) == 2 && output.inputs.modules.alerting.receivers[0].slack_configs[0].api_url_file == "/etc/alertmanager/secrets/slack-url"
    error_message = "the receivers must reach the inputs as written, their *_file keys included."
  }
  assert {
    condition     = output.inputs.modules.alerting.route.receiver == "team" && output.inputs.modules.alerting.route.routes[0].receiver == "on-call"
    error_message = "the routing tree must reach the inputs as written."
  }
  assert {
    condition     = output.inputs.modules.alerting.values.server.resources.requests.memory == "96Mi"
    error_message = "the client's chart values must reach the inputs as written."
  }
}

# The watchdog turned off in the open: no Secret is needed when no receiver
# reads a key from one.
run "alerting_turns_on_without_the_watchdog_and_without_a_secret" {
  command = plan
  variables {
    kube = {
      alerting = {
        enabled   = true
        watchdog  = false
        receivers = [{ name = "team", webhook_configs = [{ url_file = "/etc/alertmanager/secrets/team-url" }] }]
        route     = { receiver = "team" }
      }
    }
  }

  assert {
    condition     = output.inputs.modules.alerting.enabled && output.inputs.modules.alerting.watchdog == false && output.inputs.modules.alerting.receivers_secret == ""
    error_message = "watchdog = false must reach the inputs, with no Secret named."
  }
}
