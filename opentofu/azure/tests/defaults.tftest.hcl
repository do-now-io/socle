# A consumer who sets nothing gets the recommended configuration. These runs
# assert that, and that the preconditions guarding incoherent inputs fire.
#
# Mocked, not just credential-skipped: unlike aws/google, azurerm builds a
# real authorizer and contacts Azure AD to acquire a token during configure
# — even for a plan, even with every skip_*_validation-style flag set.
# There is no offline stub mode to opt into here, so the provider itself is
# mocked instead.

mock_provider "azurerm" {}

# azurerm's own SDK parses every cross-resource ID reference into its
# expected ARM segment shape during plan, even against a mock — a random
# mock ID like "LtBQZF0" fails that parse before the plan ever finishes.
# Every resource another resource in this module references by ID needs a
# realistic-looking one.
override_resource {
  target = azurerm_resource_group.socle
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/socle-test"
  }
}

override_resource {
  target = azurerm_virtual_network.socle
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/socle-test/providers/Microsoft.Network/virtualNetworks/socle-test-vnet"
  }
}

override_resource {
  target = azurerm_subnet.node
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/socle-test/providers/Microsoft.Network/virtualNetworks/socle-test-vnet/subnets/socle-test-nodes"
  }
}

override_resource {
  target = azurerm_public_ip.nat
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/socle-test/providers/Microsoft.Network/publicIPAddresses/socle-test-nat"
  }
}

override_resource {
  target = azurerm_nat_gateway.socle
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/socle-test/providers/Microsoft.Network/natGateways/socle-test-nat"
  }
}

override_resource {
  target = azurerm_log_analytics_workspace.container_insights
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/socle-test/providers/Microsoft.OperationalInsights/workspaces/socle-test-insights"
  }
}

override_resource {
  target = azurerm_monitor_workspace.socle
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/socle-test/providers/microsoft.monitor/accounts/socle-test-metrics"
  }
}

override_resource {
  target = azurerm_monitor_data_collection_rule.prometheus
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/socle-test/providers/Microsoft.Insights/dataCollectionRules/socle-test-prometheus"
  }
}

override_resource {
  target = azurerm_kubernetes_cluster.socle
  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/socle-test/providers/Microsoft.ContainerService/managedClusters/socle-test"
    private_fqdn = "socle-test-abcdef.privatelink.francecentral.azmk8s.io"
    kube_config = [
      {
        cluster_ca_certificate = "bW9jaw=="
        client_certificate     = ""
        client_key             = ""
        host                   = "https://socle-test-abcdef.privatelink.francecentral.azmk8s.io:443"
        password               = ""
        username               = ""
      }
    ]
  }
}

variables {
  cluster_name = "socle-test"
  owner        = "platform"
  environment  = "prod"
  location     = "francecentral"

  resource_group_name   = "socle-test"
  create_resource_group = true

  create_vnet = true

  kubernetes_version = "1.34"

  maintenance_window_auto_upgrade = {
    frequency   = "Weekly"
    interval    = 1
    duration    = 4
    day_of_week = "Sunday"
    start_time  = "02:00"
    utc_offset  = "+00:00"
  }

  maintenance_window_node_os = {
    frequency   = "Weekly"
    interval    = 1
    duration    = 4
    day_of_week = "Saturday"
    start_time  = "02:00"
    utc_offset  = "+00:00"
  }
}

run "defaults_are_the_recommended_position" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.socle.sku_tier == "Standard"
    error_message = "The cluster must be AKS Standard, never Automatic."
  }

  assert {
    condition     = one(azurerm_kubernetes_cluster.socle.node_provisioning_profile).mode == "Auto"
    error_message = "Node Auto-Provisioning must be on by default."
  }

  assert {
    condition     = one(azurerm_kubernetes_cluster.socle.network_profile).network_plugin == "none"
    error_message = "BYO CNI is not optional: Cilium replaces it, installed later by the factory."
  }

  assert {
    condition     = output.pod_cidr == "10.244.0.0/16"
    error_message = "pod_cidr must default to AKS's own pod range: it is Cilium's cluster pool, and the chart's own default (10.0.0.0/8) contains the VNet."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.socle.automatic_upgrade_channel == "stable"
    error_message = "The stable channel is hardcoded, not a variable."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.socle.support_plan == "KubernetesOfficial"
    error_message = "LTS must be refused by default — a cluster on stable never falls behind enough to need it."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.socle.private_cluster_enabled == true
    error_message = "Private cluster must be on by default."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.socle.private_cluster_public_fqdn_enabled == false
    error_message = "The public FQDN must stay disabled by default."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.socle.workload_identity_enabled == true
    error_message = "Entra Workload ID must be on by default."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.socle.oidc_issuer_enabled == true
    error_message = "The OIDC issuer must be on by default — workload identity federation needs it, and the checklist requires the output regardless."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.socle.azure_policy_enabled == true
    error_message = "The Azure Policy add-on must be on by default."
  }

  assert {
    condition     = one(azurerm_kubernetes_cluster.socle.default_node_pool).only_critical_addons_enabled == true
    error_message = "The mandatory system node pool must be tainted system-only by default — NAP provisions everything workload-shaped."
  }

  assert {
    condition     = length(azurerm_resource_group.socle) == 1
    error_message = "The resource group must be created by default."
  }

  assert {
    condition     = length(azurerm_virtual_network.socle) == 1
    error_message = "The VNet must be created by default."
  }

  assert {
    condition     = length(azurerm_nat_gateway.socle) == 1
    error_message = "The NAT Gateway must be created by default — the node subnet has no other egress path."
  }

  assert {
    condition     = one(azurerm_kubernetes_cluster.socle.oms_agent).log_analytics_workspace_id != null
    error_message = "Container Insights must be wired to a Log Analytics workspace by default."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.socle.tags["socle-version"] == "0.0.0" # x-release-please-version
    error_message = "Every billable resource must carry the socle version that created it."
  }
}

run "attaching_to_an_existing_resource_group_and_vnet_is_coherent" {
  command = plan

  variables {
    create_resource_group = false
    create_vnet           = false
    vnet_name             = "existing-vnet"
    node_subnet_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/existing/providers/Microsoft.Network/virtualNetworks/existing-vnet/subnets/nodes"
  }

  assert {
    condition     = length(azurerm_resource_group.socle) == 0
    error_message = "No resource group should be created when attaching to an existing one."
  }

  assert {
    condition     = length(azurerm_virtual_network.socle) == 0
    error_message = "No VNet should be created when attaching to an existing one."
  }
}

run "helm_kubernetes_is_credential_free_and_uses_kubelogin" {
  command = plan

  assert {
    condition     = output.helm_kubernetes.exec.command == "kubelogin" && contains(output.helm_kubernetes.exec.args, "azurecli")
    error_message = "helm_kubernetes must obtain its token at call time through kubelogin with the Azure CLI login, never carry one."
  }
}
