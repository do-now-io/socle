# Every validation block, tripped once. Negative cases only: the plan stops at
# variable validation, before the helm provider is ever configured, so these
# runs need no cluster. The aws provider is configured earlier than that, and
# would look for credentials a CI runner does not have: mocked.

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

# --- external_dns — docs/catalog/external-dns.md ---------------------------

run "external_dns_refuses_enabling_without_a_domain_filter" {
  command = plan
  variables { kube = { external_dns = { enabled = true } } }
  expect_failures = [var.kube]
}

run "external_dns_refuses_a_domain_filter_that_is_not_a_dns_name" {
  command = plan
  variables { kube = { external_dns = { domain_filters = [".acme.example"] } } }
  expect_failures = [var.kube]
}

run "external_dns_refuses_a_policy_outside_the_two_offered" {
  command = plan
  variables { kube = { external_dns = { policy = "create-only" } } }
  expect_failures = [var.kube]
}

run "external_dns_with_crossplane_on_aws_refuses_an_empty_region" {
  command = plan
  variables {
    kube = {
      crossplane   = { enabled = true }
      external_dns = { enabled = true, domain_filters = ["acme.example"] }
    }
  }
  expect_failures = [var.kube]
}

run "external_dns_refuses_a_credential_in_values_env" {
  command = plan
  variables { kube = { external_dns = { values = { env = [{ name = "AWS_SECRET_ACCESS_KEY", value = "wJalrXUtnFEMI" }] } } } }
  expect_failures = [var.kube]
}

run "external_dns_refuses_a_secret_flag_in_values_extra_args" {
  command = plan
  variables { kube = { external_dns = { values = { extraArgs = { txt-encrypt-aes-key = "0123456789abcdef0123456789abcdef" } } } } }
  expect_failures = [var.kube]
}

run "external_dns_refuses_the_charts_secret_configuration" {
  command = plan
  variables { kube = { external_dns = { values = { secretConfiguration = { enabled = true, data = { "credentials" = "x" } } } } } }
  expect_failures = [var.kube]
}

run "external_dns_refuses_values_that_are_not_an_object" {
  command = plan
  variables { kube = { external_dns = { values = "logLevel: debug" } } }
  expect_failures = [var.kube]
}

run "external_dns_refuses_an_invalid_values_secret_name" {
  command = plan
  variables { kube = { external_dns = { values_secret = "My_Values" } } }
  expect_failures = [var.kube]
}

run "external_dns_refuses_a_txt_owner_id_with_a_space" {
  command = plan
  variables { kube = { external_dns = { txt_owner_id = "acme prod" } } }
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
    project         = { id = "sandbox-2bace", number = "123456789012" }
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
    project         = { id = "sandbox-2bace", number = "123456789012" }
    kube            = { metrics_server = { enabled = false } }
  }
  expect_failures = [var.kube]
}

run "kube_refuses_crossplane_enabled_that_is_not_a_bool" {
  command = plan
  variables { kube = { crossplane = { enabled = "true" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_crossplane_values_that_are_not_an_object" {
  command = plan
  variables { kube = { crossplane = { values = "metrics: {enabled: true}" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_crossplane_values_carrying_a_secret_in_extra_objects" {
  command = plan
  variables { kube = { crossplane = { values = { extraObjects = [{ apiVersion = "v1", kind = "Secret", metadata = { name = "aws-creds" }, stringData = { credentials = "x" } }] } } } }
  expect_failures = [var.kube]
}

run "kube_refuses_crossplane_values_carrying_a_token_in_an_env_var" {
  command = plan
  variables { kube = { crossplane = { values = { extraEnvVarsRBACManager = { GITHUB_TOKEN = "x" } } } } }
  expect_failures = [var.kube]
}

run "kube_refuses_crossplane_values_secret_that_is_not_a_secret_name" {
  command = plan
  variables { kube = { crossplane = { values_secret = "Crossplane_Values" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_crossplane_values_secret_that_is_not_a_string" {
  command = plan
  variables { kube = { crossplane = { values_secret = ["crossplane-values"] } } }
  expect_failures = [var.kube]
}

run "kube_refuses_crossplane_permissions_boundary_that_is_not_a_policy_arn" {
  command = plan
  variables { kube = { crossplane = { permissions_boundary = "arn:aws:iam::123456789012:role/crossplane" } } }
  expect_failures = [var.kube]
}

run "region_refuses_a_display_name" {
  command = plan
  variables { region = "Europe (Paris)" }
  expect_failures = [var.region]
}

run "kube_refuses_argocd_ha_that_is_not_a_bool" {
  command = plan
  variables { kube = { argocd = { ha = "yes" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_argocd_admin_enabled_that_is_not_a_bool" {
  command = plan
  variables { kube = { argocd = { admin_enabled = 1 } } }
  expect_failures = [var.kube]
}

run "kube_refuses_argocd_domain_that_is_not_a_string" {
  command = plan
  variables { kube = { argocd = { domain = ["argocd.acme.example"] } } }
  expect_failures = [var.kube]
}

run "kube_refuses_argocd_domain_with_a_scheme" {
  command = plan
  variables { kube = { argocd = { domain = "https://argocd.acme.example" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_argocd_domain_that_is_a_bare_label" {
  command = plan
  variables { kube = { argocd = { domain = "argocd" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_argocd_values_that_are_not_an_object" {
  command = plan
  variables { kube = { argocd = { values = "configs: {}" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_argocd_values_carrying_the_argocd_secret" {
  command = plan
  variables { kube = { argocd = { values = { configs = { secret = { argocdServerAdminPassword = "x" } } } } } }
  expect_failures = [var.kube]
}

run "kube_refuses_argocd_values_carrying_credential_templates" {
  command = plan
  variables { kube = { argocd = { values = { configs = { credentialTemplates = { github = { url = "https://github.com/acme", password = "x" } } } } } } }
  expect_failures = [var.kube]
}

run "kube_refuses_argocd_values_carrying_a_repository_private_key" {
  command = plan
  variables { kube = { argocd = { values = { configs = { repositories = { app = { url = "https://github.com/acme/app", githubAppID = "1", githubAppPrivateKey = "-----BEGIN" } } } } } } }
  expect_failures = [var.kube]
}

run "kube_refuses_argocd_values_secret_that_is_not_a_secret_name" {
  command = plan
  variables { kube = { argocd = { values_secret = "ArgoCD_Values" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_victoria_metrics_enabled_that_is_not_a_bool" {
  command = plan
  variables { kube = { victoria_metrics = { enabled = "true" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_victoria_metrics_retention_that_is_not_a_string" {
  command = plan
  variables { kube = { victoria_metrics = { retention = 15 } } }
  expect_failures = [var.kube]
}

run "kube_refuses_victoria_metrics_retention_spelt_out" {
  command = plan
  variables { kube = { victoria_metrics = { retention = "15days" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_victoria_metrics_retention_under_a_day" {
  command = plan
  variables { kube = { victoria_metrics = { retention = "12h" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_victoria_metrics_retention_of_zero" {
  command = plan
  variables { kube = { victoria_metrics = { retention = "0d" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_victoria_metrics_storage_size_that_is_not_a_string" {
  command = plan
  variables { kube = { victoria_metrics = { storage_size = 20 } } }
  expect_failures = [var.kube]
}

run "kube_refuses_victoria_metrics_storage_size_in_decimal_units" {
  command = plan
  variables { kube = { victoria_metrics = { storage_size = "20GB" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_victoria_metrics_values_that_are_not_an_object" {
  command = plan
  variables { kube = { victoria_metrics = { values = "server: {}" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_victoria_metrics_values_carrying_an_auth_password_flag" {
  command = plan
  variables { kube = { victoria_metrics = { values = { server = { extraArgs = { "httpAuth.password" = "x" } } } } } }
  expect_failures = [var.kube]
}

run "kube_refuses_victoria_metrics_values_carrying_an_auth_key_flag" {
  command = plan
  variables { kube = { victoria_metrics = { values = { server = { extraArgs = { deleteAuthKey = "x" } } } } } }
  expect_failures = [var.kube]
}

run "kube_refuses_victoria_metrics_values_carrying_a_literal_credential_env" {
  command = plan
  variables { kube = { victoria_metrics = { values = { server = { env = [{ name = "VM_httpAuth_password", value = "x" }] } } } } }
  expect_failures = [var.kube]
}

run "kube_refuses_victoria_metrics_values_carrying_a_secret_among_extra_objects" {
  command = plan
  variables { kube = { victoria_metrics = { values = { extraObjects = [{ apiVersion = "v1", kind = "Secret", metadata = { name = "vm-auth" } }] } } } }
  expect_failures = [var.kube]
}

run "kube_refuses_victoria_metrics_values_secret_that_is_not_a_secret_name" {
  command = plan
  variables { kube = { victoria_metrics = { values_secret = "VM_Values" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_otel_agent_enabled_that_is_not_a_bool" {
  command = plan
  variables { kube = { otel_agent = { enabled = "yes" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_otel_agent_values_that_are_not_an_object" {
  command = plan
  variables { kube = { otel_agent = { values = "mode: daemonset" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_otel_agent_values_carrying_a_literal_bearer_token" {
  command = plan
  variables { kube = { otel_agent = { values = { config = { extensions = { bearertokenauth = { token = "abc123" } } } } } } }
  expect_failures = [var.kube]
}

run "kube_refuses_otel_agent_values_carrying_a_literal_basic_auth_password" {
  command = plan
  variables { kube = { otel_agent = { values = { config = { extensions = { "basicauth/client" = { client_auth = { username = "u", password = "p" } } } } } } } }
  expect_failures = [var.kube]
}

run "kube_refuses_otel_agent_values_carrying_a_literal_authorization_header" {
  command = plan
  variables { kube = { otel_agent = { values = { config = { exporters = { "otlp_http/saas" = { endpoint = "https://otlp.example", headers = { Authorization = "Bearer abc123" } } } } } } } }
  expect_failures = [var.kube]
}

run "kube_refuses_otel_agent_values_carrying_a_literal_credential_env" {
  command = plan
  variables { kube = { otel_agent = { values = { extraEnvs = [{ name = "SAAS_API_KEY", value = "abc123" }] } } } }
  expect_failures = [var.kube]
}

run "kube_refuses_otel_agent_values_carrying_a_secret_among_extra_manifests" {
  command = plan
  variables { kube = { otel_agent = { values = { extraManifests = [{ apiVersion = "v1", kind = "Secret", metadata = { name = "saas" } }] } } } }
  expect_failures = [var.kube]
}

run "kube_refuses_otel_agent_values_secret_that_is_not_a_secret_name" {
  command = plan
  variables { kube = { otel_agent = { values_secret = "Otel_Values" } } }
  expect_failures = [var.kube]
}

run "eks_addons_refuses_a_value_that_is_not_an_object" {
  command = plan
  variables { eks_addons = "all" }
  expect_failures = [var.eks_addons]
}

run "eks_addons_refuses_an_unknown_addon" {
  command = plan
  variables { eks_addons = { vpc_cni = true } }
  expect_failures = [var.eks_addons]
}

run "eks_addons_refuses_a_value_that_is_not_a_bool" {
  command = plan
  variables { eks_addons = { ebs_csi = "yes" } }
  expect_failures = [var.eks_addons]
}

run "eks_addons_is_refused_off_aws" {
  command = plan
  variables {
    cloud           = "gcp"
    eks_addons      = { ebs_csi = false }
    cluster_network = null
    project         = { id = "sandbox-2bace", number = "123456789012" }
  }
  expect_failures = [var.eks_addons]
}

run "eks_addons_refuses_a_storage_driver_without_the_pod_identity_agent" {
  command = plan
  variables { eks_addons = { pod_identity_agent = false } }
  expect_failures = [var.eks_addons]
}

run "kube_refuses_an_argocd_gateway_that_is_not_one_of_the_shared_ones" {
  command = plan
  variables { kube = { argocd = { gateway = "internal" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_gateway_api_gateways_that_is_not_a_bool" {
  command = plan
  variables { kube = { gateway_api = { gateways = "yes" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_otel_gateway_enabled_that_is_not_a_bool" {
  command = plan
  variables { kube = { otel_gateway = { enabled = 1 } } }
  expect_failures = [var.kube]
}

run "kube_refuses_otel_gateway_values_that_are_not_an_object" {
  command = plan
  variables { kube = { otel_gateway = { values = ["mode: deployment"] } } }
  expect_failures = [var.kube]
}

run "kube_refuses_otel_gateway_values_carrying_a_literal_oauth2_client_secret" {
  command = plan
  variables { kube = { otel_gateway = { values = { config = { extensions = { oauth2client = { client_id = "id", client_secret = "s3cr3t" } } } } } } }
  expect_failures = [var.kube]
}

run "kube_refuses_otel_gateway_values_carrying_a_literal_api_key_header" {
  command = plan
  variables { kube = { otel_gateway = { values = { config = { exporters = { "otlp_http/saas" = { endpoint = "https://otlp.example", headers = { "X-API-Key" = "abc123" } } } } } } } }
  expect_failures = [var.kube]
}

run "kube_refuses_otel_gateway_values_secret_that_is_not_a_secret_name" {
  command = plan
  variables { kube = { otel_gateway = { values_secret = "gateway values" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_grafana_enabled_that_is_not_a_bool" {
  command = plan
  variables { kube = { grafana = { enabled = "on" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_grafana_domain_with_a_scheme" {
  command = plan
  variables { kube = { grafana = { domain = "https://grafana.acme.example" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_grafana_domain_that_is_a_bare_label" {
  command = plan
  variables { kube = { grafana = { domain = "grafana" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_grafana_values_carrying_the_admin_password" {
  command = plan
  variables { kube = { grafana = { values = { adminPassword = "hunter2" } } } }
  expect_failures = [var.kube]
}

run "kube_refuses_grafana_values_carrying_the_secret_key" {
  command = plan
  variables { kube = { grafana = { values = { "grafana.ini" = { security = { secret_key = "x" } } } } } }
  expect_failures = [var.kube]
}

run "kube_refuses_grafana_values_carrying_an_oauth_client_secret" {
  command = plan
  variables { kube = { grafana = { values = { "grafana.ini" = { "auth.generic_oauth" = { enabled = true, client_id = "id", client_secret = "s3cr3t" } } } } } }
  expect_failures = [var.kube]
}

run "kube_refuses_grafana_values_carrying_a_literal_datasource_secret" {
  command = plan
  variables {
    kube = { grafana = { values = { datasources = { "extra.yaml" = { apiVersion = 1, datasources = [{ name = "pg", type = "postgres", secureJsonData = { password = "hunter2" } }] } } } } }
  }
  expect_failures = [var.kube]
}

run "kube_refuses_grafana_values_carrying_a_credential_env" {
  command = plan
  variables { kube = { grafana = { values = { env = { GF_SECURITY_ADMIN_PASSWORD = "hunter2" } } } } }
  expect_failures = [var.kube]
}

run "kube_refuses_grafana_values_carrying_a_secret_among_extra_objects" {
  command = plan
  variables { kube = { grafana = { values = { extraObjects = [{ apiVersion = "v1", kind = "Secret", metadata = { name = "x" } }] } } } }
  expect_failures = [var.kube]
}

run "kube_refuses_grafana_values_secret_that_is_not_a_secret_name" {
  command = plan
  variables { kube = { grafana = { values_secret = "Grafana_Values" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_otel_agent_logs_that_is_not_a_bool" {
  command = plan
  variables { kube = { otel_agent = { logs = "yes" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_victoria_logs_retention_under_a_day" {
  command = plan
  variables { kube = { victoria_logs = { retention = "6h" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_victoria_logs_retention_that_is_not_a_string" {
  command = plan
  variables { kube = { victoria_logs = { retention = 7 } } }
  expect_failures = [var.kube]
}

run "kube_refuses_victoria_logs_storage_size_in_decimal_units" {
  command = plan
  variables { kube = { victoria_logs = { storage_size = "20G" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_victoria_logs_values_carrying_an_auth_password_flag" {
  command = plan
  variables { kube = { victoria_logs = { values = { server = { extraArgs = { "httpAuth.password" = "x" } } } } } }
  expect_failures = [var.kube]
}

run "kube_refuses_victoria_logs_values_secret_that_is_not_a_secret_name" {
  command = plan
  variables { kube = { victoria_logs = { values_secret = "VL_Values" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_victoria_traces_enabled_that_is_not_a_bool" {
  command = plan
  variables { kube = { victoria_traces = { enabled = 1 } } }
  expect_failures = [var.kube]
}

run "kube_refuses_victoria_traces_retention_spelt_out" {
  command = plan
  variables { kube = { victoria_traces = { retention = "one week" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_victoria_traces_storage_size_without_a_unit" {
  command = plan
  variables { kube = { victoria_traces = { storage_size = "10" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_victoria_traces_values_carrying_a_literal_credential_env" {
  command = plan
  variables { kube = { victoria_traces = { values = { server = { env = [{ name = "VM_httpAuth_password", value = "x" }] } } } } }
  expect_failures = [var.kube]
}

run "kube_refuses_victoria_traces_values_secret_that_is_not_a_secret_name" {
  command = plan
  variables { kube = { victoria_traces = { values_secret = "VT_Values" } } }
  expect_failures = [var.kube]
}

# --- keda — docs/catalog/keda.md -------------------------------------------

run "keda_refuses_a_service_it_cannot_scope" {
  command = plan
  variables {
    region = "eu-west-3"
    kube = {
      crossplane = { enabled = true }
      keda       = { enabled = true, services = ["sqs", "rds"] }
    }
  }
  expect_failures = [var.kube]
}

run "keda_refuses_a_wildcard_service" {
  command = plan
  variables {
    region = "eu-west-3"
    kube = {
      crossplane = { enabled = true }
      keda       = { enabled = true, services = ["*"] }
    }
  }
  expect_failures = [var.kube]
}

run "keda_refuses_a_service_without_crossplane" {
  command = plan
  variables {
    region = "eu-west-3"
    kube   = { keda = { enabled = true, services = ["sqs"] } }
  }
  expect_failures = [var.kube]
}

# Each cloud's list is its own: an AWS service on gcp is a service the gcp
# template cannot scope, and so is GCP's on aws.
run "keda_services_are_the_clouds_own" {
  command = plan
  variables {
    cloud           = "gcp"
    cluster_network = null
    project         = { id = "sandbox-2bace", number = "123456789012" }
    region          = "europe-west1"
    kube = {
      crossplane = { enabled = true }
      keda       = { enabled = true, services = ["sqs"] }
    }
  }
  expect_failures = [var.kube]
}

run "keda_refuses_a_gcp_service_on_aws" {
  command = plan
  variables {
    region = "eu-west-3"
    kube = {
      crossplane = { enabled = true }
      keda       = { enabled = true, services = ["pubsub"] }
    }
  }
  expect_failures = [var.kube]
}

run "keda_refuses_a_service_where_the_socle_declares_no_role" {
  command = plan
  variables {
    cloud = "azure"
    kube = {
      crossplane = { enabled = true }
      keda       = { enabled = true, services = ["sqs"] }
    }
  }
  expect_failures = [var.kube]
}

run "keda_with_a_service_on_aws_refuses_an_empty_region" {
  command = plan
  variables {
    kube = {
      crossplane = { enabled = true }
      keda       = { enabled = true, services = ["sqs"] }
    }
  }
  expect_failures = [var.kube]
}

run "keda_refuses_services_that_are_not_a_list" {
  command = plan
  variables { kube = { keda = { services = "sqs" } } }
  expect_failures = [var.kube]
}

run "keda_refuses_a_credential_in_values_env" {
  command = plan
  variables { kube = { keda = { values = { operator = { env = [{ name = "AWS_SECRET_ACCESS_KEY", value = "wJalrXUtnFEMI" }] } } } } }
  expect_failures = [var.kube]
}

run "keda_refuses_a_secret_among_extra_objects" {
  command = plan
  variables {
    kube = {
      keda = {
        values = {
          extraObjects = [{ apiVersion = "v1", kind = "Secret", metadata = { name = "sqs-keys" }, stringData = { k = "v" } }]
        }
      }
    }
  }
  expect_failures = [var.kube]
}

run "keda_refuses_values_that_are_not_an_object" {
  command = plan
  variables { kube = { keda = { values = "webhooks: {}" } } }
  expect_failures = [var.kube]
}

run "keda_refuses_an_invalid_values_secret_name" {
  command = plan
  variables { kube = { keda = { values_secret = "My_Values" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_kyverno_enabled_that_is_not_a_bool" {
  command = plan
  variables { kube = { kyverno = { enabled = "yes" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_kyverno_values_carrying_registry_credentials" {
  command = plan
  variables { kube = { kyverno = { values = { imagePullSecrets = { regcred = { registry = "r.example", username = "u", password = "p" } } } } } }
  expect_failures = [var.kube]
}

run "kube_refuses_kyverno_values_carrying_a_literal_credential_env" {
  command = plan
  variables { kube = { kyverno = { values = { reportsController = { extraEnvVars = [{ name = "REGISTRY_PASSWORD", value = "x" }] } } } } }
  expect_failures = [var.kube]
}

run "kube_refuses_kyverno_values_secret_that_is_not_a_secret_name" {
  command = plan
  variables { kube = { kyverno = { values_secret = "Kyverno_Values" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_kyverno_policies_without_the_engine" {
  command = plan
  variables { kube = { kyverno_policies = { enabled = true } } }
  expect_failures = [var.kube]
}

run "kube_refuses_kyverno_policies_profile_unknown" {
  command = plan
  variables { kube = { kyverno = { enabled = true }, kyverno_policies = { enabled = true, profile = "privileged" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_kyverno_policies_enforce_that_is_not_a_list" {
  command = plan
  variables { kube = { kyverno = { enabled = true }, kyverno_policies = { enabled = true, enforce = "disallow-privileged-containers" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_kyverno_policies_enforce_naming_an_unknown_policy" {
  command = plan
  variables { kube = { kyverno = { enabled = true }, kyverno_policies = { enabled = true, enforce = ["disallow-everything"] } } }
  expect_failures = [var.kube]
}

run "kube_refuses_kyverno_policies_enforce_naming_a_restricted_policy_on_baseline" {
  command = plan
  variables { kube = { kyverno = { enabled = true }, kyverno_policies = { enabled = true, enforce = ["require-run-as-nonroot"] } } }
  expect_failures = [var.kube]
}

run "kube_refuses_kyverno_policies_enforce_naming_the_registry_policy_without_an_allow_list" {
  command = plan
  variables { kube = { kyverno = { enabled = true }, kyverno_policies = { enabled = true, enforce = ["restrict-image-registries"] } } }
  expect_failures = [var.kube]
}

run "kube_refuses_kyverno_policies_allowed_registries_with_a_scheme" {
  command = plan
  variables { kube = { kyverno = { enabled = true }, kyverno_policies = { enabled = true, allowed_registries = ["https://ghcr.io"] } } }
  expect_failures = [var.kube]
}

run "kube_refuses_kyverno_policies_allowed_registries_with_a_trailing_slash" {
  command = plan
  variables { kube = { kyverno = { enabled = true }, kyverno_policies = { enabled = true, allowed_registries = ["ghcr.io/"] } } }
  expect_failures = [var.kube]
}

run "kube_refuses_kyverno_policies_allowed_registries_without_a_host" {
  command = plan
  variables { kube = { kyverno = { enabled = true }, kyverno_policies = { enabled = true, allowed_registries = ["nginx"] } } }
  expect_failures = [var.kube]
}

run "kube_refuses_kyverno_policies_values_secret_that_is_not_a_secret_name" {
  command = plan
  variables { kube = { kyverno_policies = { values_secret = "Policies_Values" } } }
  expect_failures = [var.kube]
}

# --- reloader — docs/catalog/reloader.md -----------------------------------

run "reloader_refuses_auto_reload_all" {
  command = plan
  variables { kube = { reloader = { enabled = true, values = { reloader = { autoReloadAll = true } } } } }
  expect_failures = [var.kube]
}

run "reloader_refuses_a_literal_secret_env" {
  command = plan
  variables { kube = { reloader = { values = { reloader = { deployment = { env = { secret = { ALERT_WEBHOOK_URL = "https://hooks.slack.com/x" } } } } } } } }
  expect_failures = [var.kube]
}

run "reloader_refuses_an_open_env_named_like_a_credential" {
  command = plan
  variables { kube = { reloader = { values = { reloader = { deployment = { env = { open = { ALERT_WEBHOOK_URL = "https://hooks.slack.com/x" } } } } } } } }
  expect_failures = [var.kube]
}

run "reloader_refuses_values_that_are_not_an_object" {
  command = plan
  variables { kube = { reloader = { values = "reloader: {}" } } }
  expect_failures = [var.kube]
}

run "reloader_refuses_an_invalid_values_secret_name" {
  command = plan
  variables { kube = { reloader = { values_secret = "Reloader_Values" } } }
  expect_failures = [var.kube]
}

run "reloader_refuses_an_unknown_attribute" {
  command = plan
  variables { kube = { reloader = { auto_reload_all = true } } }
  expect_failures = [var.kube]
}

# --- external_secrets — docs/catalog/external-secrets.md -------------------

run "external_secrets_refuses_a_wildcard_prefix" {
  command = plan
  variables { kube = { external_secrets = { prefixes = ["*"] } } }
  expect_failures = [var.kube]
}

run "external_secrets_refuses_a_prefix_with_a_trailing_slash" {
  command = plan
  variables { kube = { external_secrets = { prefixes = ["acme/"] } } }
  expect_failures = [var.kube]
}

run "external_secrets_refuses_a_prefix_with_an_empty_segment" {
  command = plan
  variables { kube = { external_secrets = { prefixes = ["acme//prod"] } } }
  expect_failures = [var.kube]
}

run "external_secrets_refuses_prefixes_that_are_not_a_list" {
  command = plan
  variables { kube = { external_secrets = { prefixes = "acme" } } }
  expect_failures = [var.kube]
}

run "external_secrets_with_crossplane_on_aws_refuses_an_empty_region" {
  command = plan
  variables {
    kube = {
      crossplane       = { enabled = true }
      external_secrets = { enabled = true }
    }
  }
  expect_failures = [var.kube]
}

run "external_secrets_refuses_a_literal_credential_in_extra_env" {
  command = plan
  variables { kube = { external_secrets = { values = { extraEnv = [{ name = "AWS_SECRET_ACCESS_KEY", value = "wJalrXUtnFEMI" }] } } } }
  expect_failures = [var.kube]
}

run "external_secrets_refuses_a_secret_among_extra_objects" {
  command = plan
  variables {
    kube = {
      external_secrets = {
        values = {
          extraObjects = [{ apiVersion = "v1", kind = "Secret", metadata = { name = "aws-keys" }, stringData = { k = "v" } }]
        }
      }
    }
  }
  expect_failures = [var.kube]
}

run "external_secrets_refuses_an_invalid_values_secret_name" {
  command = plan
  variables { kube = { external_secrets = { values_secret = "ESO_Values" } } }
  expect_failures = [var.kube]
}

# --- velero ---

run "kube_refuses_velero_on_aws_without_crossplane" {
  command = plan
  variables {
    region = "eu-west-3"
    kube   = { velero = { enabled = true } }
  }
  expect_failures = [var.kube]
}

run "kube_refuses_velero_on_aws_without_a_region" {
  command = plan
  variables {
    kube = { crossplane = { enabled = true }, velero = { enabled = true } }
  }
  expect_failures = [var.kube]
}

run "kube_refuses_velero_on_azure" {
  command = plan
  variables {
    cloud = "azure"
    kube  = { velero = { enabled = false } }
  }
  expect_failures = [var.kube]
}

run "kube_refuses_velero_on_scaleway" {
  command = plan
  variables {
    cloud           = "scaleway"
    cluster_network = null
    kube            = { velero = { enabled = false } }
  }
  expect_failures = [var.kube]
}

run "kube_refuses_velero_on_gcp_without_crossplane" {
  command = plan
  variables {
    cloud           = "gcp"
    cluster_network = null
    project         = { id = "sandbox-2bace", number = "123456789012" }
    region          = "europe-west1"
    kube            = { velero = { enabled = true } }
  }
  expect_failures = [var.kube]
}

run "kube_refuses_velero_on_gcp_without_a_region" {
  command = plan
  variables {
    cloud           = "gcp"
    cluster_network = null
    project         = { id = "sandbox-2bace", number = "123456789012" }
    kube            = { crossplane = { enabled = true }, velero = { enabled = true } }
  }
  expect_failures = [var.kube]
}

# Autopilot refuses the node-agent's hostPath mount of the kubelet's pods
# directory, so the DaemonSet would never schedule: refused at plan.
run "velero_node_agent_is_refused_on_gcp" {
  command = plan
  variables {
    cloud           = "gcp"
    cluster_network = null
    project         = { id = "sandbox-2bace", number = "123456789012" }
    region          = "europe-west1"
    kube = {
      crossplane = { enabled = true }
      velero     = { enabled = true, node_agent = true }
    }
  }
  expect_failures = [var.kube]
}

run "kube_refuses_a_velero_policy_with_a_retention_in_weeks" {
  command = plan
  variables { kube = { velero = { policies = [{ frequency = "daily", retention = "2w", schedule = "0 2 * * *" }] } } }
  expect_failures = [var.kube]
}

run "kube_refuses_a_velero_policy_with_an_unknown_key" {
  command = plan
  variables { kube = { velero = { policies = [{ frequency = "daily", retention = "7d", schedule = "0 2 * * *", ttl = "168h" }] } } }
  expect_failures = [var.kube]
}

run "kube_refuses_a_velero_policy_with_a_frequency_that_is_not_a_label_value" {
  command = plan
  variables { kube = { velero = { policies = [{ frequency = "Daily", retention = "7d", schedule = "0 2 * * *" }] } } }
  expect_failures = [var.kube]
}

run "kube_refuses_a_velero_policy_with_a_six_field_cron" {
  command = plan
  variables { kube = { velero = { policies = [{ frequency = "daily", retention = "7d", schedule = "0 0 2 * * *" }] } } }
  expect_failures = [var.kube]
}

run "kube_refuses_a_velero_pair_twice" {
  command = plan
  variables {
    kube = { velero = { policies = [
      { frequency = "daily", retention = "7d", schedule = "0 2 * * *" },
      { frequency = "daily", retention = "7d", schedule = "0 4 * * *" },
    ] } }
  }
  expect_failures = [var.kube]
}

run "kube_refuses_velero_policies_that_are_not_a_list" {
  command = plan
  variables { kube = { velero = { policies = { daily = "7d" } } } }
  expect_failures = [var.kube]
}

run "kube_refuses_velero_values_carrying_secret_contents" {
  command = plan
  variables { kube = { velero = { values = { credentials = { secretContents = { cloud = "[default]" } } } } } }
  expect_failures = [var.kube]
}

run "kube_refuses_velero_values_carrying_a_literal_credential_env" {
  command = plan
  variables { kube = { velero = { values = { configuration = { extraEnvVars = [{ name = "AWS_SECRET_ACCESS_KEY", value = "x" }] } } } } }
  expect_failures = [var.kube]
}

run "kube_refuses_velero_values_secret_that_is_not_a_secret_name" {
  command = plan
  variables { kube = { velero = { values_secret = "Velero_Values" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_metrics_server_ha_that_is_not_a_bool" {
  command = plan
  variables { kube = { metrics_server = { ha = "yes" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_metrics_server_values_that_are_not_an_object" {
  command = plan
  variables { kube = { metrics_server = { values = "args: []" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_metrics_server_values_secret_that_is_not_a_secret_name" {
  command = plan
  variables { kube = { metrics_server = { values_secret = "Metrics_Server_Values" } } }
  expect_failures = [var.kube]
}

# The two forms of the flag, one per list the chart reads: alone in args, the
# way every tutorial writes it, and with a value in defaultArgs.
run "kube_refuses_metrics_server_kubelet_insecure_tls_in_args" {
  command = plan
  variables { kube = { metrics_server = { values = { args = ["--v=2", "--kubelet-insecure-tls"] } } } }
  expect_failures = [var.kube]
}

run "kube_refuses_metrics_server_kubelet_insecure_tls_with_a_value_in_default_args" {
  command = plan
  variables { kube = { metrics_server = { values = { defaultArgs = ["--cert-dir=/tmp", "--kubelet-insecure-tls=true"] } } } }
  expect_failures = [var.kube]
}

# Offered on aws only: every other cloud ships its own, and two cannot coexist.
run "kube_refuses_metrics_server_on_gcp" {
  command = plan
  variables {
    cloud           = "gcp"
    cluster_network = null
    kube            = { metrics_server = { enabled = true } }
    project         = { id = "sandbox-2bace", number = "123456789012" }
  }
  expect_failures = [var.kube]
}

run "kube_refuses_metrics_server_on_azure" {
  command = plan
  variables {
    cloud = "azure"
    kube  = { metrics_server = { enabled = true } }
  }
  expect_failures = [var.kube]
}

run "kube_refuses_metrics_server_on_scaleway" {
  command = plan
  variables {
    cloud           = "scaleway"
    cluster_network = null
    kube            = { metrics_server = { enabled = true } }
  }
  expect_failures = [var.kube]
}

# --- crossplane per cloud --------------------------------------------------

run "crossplane_permissions_boundary_is_refused_on_gcp" {
  command = plan
  variables {
    cloud           = "gcp"
    cluster_network = null
    project         = { id = "sandbox-2bace", number = "123456789012" }
    kube            = { crossplane = { permissions_boundary = "arn:aws:iam::123456789012:policy/socle/socle-test/socle-test-crossplane-boundary" } }
  }
  expect_failures = [var.kube]
}

run "crossplane_dns_records_role_is_refused_off_gcp" {
  command = plan
  variables { kube = { crossplane = { dns_records_role = "projects/sandbox-2bace/roles/socleDnsRecords_socle_test" } } }
  expect_failures = [var.kube]
}

# Crossplane holds nothing of Cloud DNS (measured 2026-10-07: a zone's IAM
# granted on the zone is never honoured), so there is no zone list to give it.
run "crossplane_takes_no_dns_zones" {
  command = plan
  variables {
    cloud           = "gcp"
    cluster_network = null
    project         = { id = "sandbox-2bace", number = "123456789012" }
    kube            = { crossplane = { dns_zones = ["sandbox-gcp-do-now-io"] } }
  }
  expect_failures = [var.kube]
}

run "crossplane_refuses_a_dns_records_role_that_is_not_a_custom_role" {
  command = plan
  variables {
    cloud           = "gcp"
    cluster_network = null
    project         = { id = "sandbox-2bace", number = "123456789012" }
    kube            = { crossplane = { dns_records_role = "roles/dns.admin" } }
  }
  expect_failures = [var.kube]
}

# --- external_secrets per cloud --------------------------------------------

# A Secret Manager secret id has no path: a "/" in a prefix would match no
# secret on gcp, and the binding would grant nothing, silently.
run "external_secrets_refuses_a_path_prefix_on_gcp" {
  command = plan
  variables {
    cloud           = "gcp"
    cluster_network = null
    project         = { id = "sandbox-2bace", number = "123456789012" }
    kube            = { external_secrets = { prefixes = ["shared/platform"] } }
  }
  expect_failures = [var.kube]
}

# "_" separates the prefix from the name on gcp: acme_prod as a prefix would
# make acme's binding read it too.
run "external_secrets_refuses_an_underscore_in_a_prefix_on_gcp" {
  command = plan
  variables {
    cloud           = "gcp"
    cluster_network = null
    project         = { id = "sandbox-2bace", number = "123456789012" }
    kube            = { external_secrets = { prefixes = ["acme_prod"] } }
  }
  expect_failures = [var.kube]
}

# --- project — gcp ---------------------------------------------------------

run "gcp_requires_its_project" {
  command = plan
  variables {
    cloud           = "gcp"
    cluster_network = null
  }
  expect_failures = [var.project]
}

run "project_is_refused_off_gcp" {
  command = plan
  variables { project = { id = "sandbox-2bace", number = "123456789012" } }
  expect_failures = [var.project]
}

run "project_refuses_an_id_that_is_not_a_project_id" {
  command = plan
  variables {
    cloud           = "gcp"
    cluster_network = null
    project         = { id = "Sandbox_2bace", number = "123456789012" }
  }
  expect_failures = [var.project]
}

run "project_refuses_a_number_that_is_not_a_number" {
  command = plan
  variables {
    cloud           = "gcp"
    cluster_network = null
    project         = { id = "sandbox-2bace", number = "sandbox-2bace" }
  }
  expect_failures = [var.project]
}

run "kube_refuses_alerting_watchdog_that_is_not_a_bool" {
  command = plan
  variables { kube = { alerting = { watchdog = "yes" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_alerting_receivers_that_are_not_a_list" {
  command = plan
  variables { kube = { alerting = { receivers = { team = {} } } } }
  expect_failures = [var.kube]
}

# vmalert evaluates every rule against VictoriaMetrics: without it, nothing can fire.
run "kube_refuses_alerting_without_victoria_metrics" {
  command = plan
  variables { kube = { alerting = { enabled = true, receivers_secret = "alerting-keys", receivers = [{ name = "team", webhook_configs = [{ url_file = "/etc/alertmanager/secrets/team-url" }] }], route = { receiver = "team" } }, victoria_metrics = { enabled = false } } }
  expect_failures = [var.kube]
}

# On, alerts must go somewhere the client named.
run "kube_refuses_alerting_on_without_a_receiver" {
  command = plan
  variables { kube = { alerting = { enabled = true, receivers_secret = "alerting-keys" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_alerting_a_route_to_a_receiver_that_does_not_exist" {
  command = plan
  variables { kube = { alerting = { enabled = true, receivers_secret = "alerting-keys", receivers = [{ name = "team", webhook_configs = [{ url_file = "/etc/alertmanager/secrets/team-url" }] }], route = { receiver = "on-call" } } } }
  expect_failures = [var.kube]
}

# The chart's default receiver drops every alert.
run "kube_refuses_alerting_a_receiver_named_devnull" {
  command = plan
  variables { kube = { alerting = { enabled = true, receivers_secret = "alerting-keys", receivers = [{ name = "devnull" }], route = { receiver = "devnull" } } } }
  expect_failures = [var.kube]
}

# Alertmanager refuses its whole configuration over a route to a receiver it does not have.
run "kube_refuses_alerting_a_sub_route_to_an_unknown_receiver" {
  command = plan
  variables { kube = { alerting = { enabled = true, receivers_secret = "alerting-keys", receivers = [{ name = "team", webhook_configs = [{ url_file = "/etc/alertmanager/secrets/team-url" }] }], route = { receiver = "team", routes = [{ receiver = "on-call", matchers = ["severity=\"critical\""] }] } } } }
  expect_failures = [var.kube]
}

# The watchdog's URL is a key: it is read from receivers_secret, which must be named.
run "kube_refuses_alerting_on_without_receivers_secret_for_the_watchdog" {
  command = plan
  variables { kube = { alerting = { enabled = true, receivers = [{ name = "team", webhook_configs = [{ url_file = "/etc/alertmanager/secrets/team-url" }] }], route = { receiver = "team" } } } }
  expect_failures = [var.kube]
}

# A Slack webhook URL is a key: whoever holds it posts in the channel.
run "kube_refuses_alerting_a_slack_api_url_in_clear" {
  command = plan
  variables { kube = { alerting = { receivers = [{ name = "team", slack_configs = [{ api_url = "https://hooks.slack.com/services/T0/B0/x" }] }] } } }
  expect_failures = [var.kube]
}

# Receivers of different kinds are a tuple, not a list: the key in clear in
# the second one must still be found.
run "kube_refuses_alerting_a_key_in_clear_beside_a_receiver_of_another_kind" {
  command = plan
  variables {
    kube = {
      alerting = {
        receivers = [
          { name = "team", slack_configs = [{ api_url_file = "/etc/alertmanager/secrets/slack-url", channel = "#alerts" }] },
          { name = "on-call", pagerduty_configs = [{ routing_key = "R0123456789" }] },
        ]
      }
    }
  }
  expect_failures = [var.kube]
}

run "kube_refuses_alerting_an_http_config_password_in_clear" {
  command = plan
  variables { kube = { alerting = { receivers = [{ name = "team", webhook_configs = [{ url_file = "/x", http_config = { basic_auth = { username = "a", password = "b" } } }] }] } } }
  expect_failures = [var.kube]
}

# v1 ships the socle's rules only, checked in CI.
run "kube_refuses_alerting_rules_in_values" {
  command = plan
  variables { kube = { alerting = { values = { server = { config = { alerts = { groups = [{ name = "mine", rules = [] }] } } } } } } }
  expect_failures = [var.kube]
}

run "kube_refuses_alerting_a_rule_path_in_values" {
  command = plan
  variables { kube = { alerting = { values = { server = { extraArgs = { rule = ["/etc/mine/*.yaml"] } } } } } }
  expect_failures = [var.kube]
}

# Rendered from receivers, route and the watchdog; values would replace its lists.
run "kube_refuses_alerting_alertmanager_config_in_values" {
  command = plan
  variables { kube = { alerting = { values = { alertmanager = { config = { route = { receiver = "x" } } } } } } }
  expect_failures = [var.kube]
}

run "kube_refuses_alerting_alertmanager_turned_off" {
  command = plan
  variables { kube = { alerting = { values = { alertmanager = { enabled = false } } } } }
  expect_failures = [var.kube]
}

run "kube_refuses_alerting_a_datasource_password_in_values" {
  command = plan
  variables { kube = { alerting = { values = { server = { datasource = { basicAuth = { password = "x" } } } } } } }
  expect_failures = [var.kube]
}

run "kube_refuses_alerting_receivers_secret_that_is_not_a_secret_name" {
  command = plan
  variables { kube = { alerting = { receivers_secret = "Alerting_Keys" } } }
  expect_failures = [var.kube]
}

run "kube_refuses_alerting_values_secret_that_is_not_a_secret_name" {
  command = plan
  variables { kube = { alerting = { values_secret = "Alerting_Values" } } }
  expect_failures = [var.kube]
}
