# The outputs, as a root reads them. These runs apply against the mocked
# azurerm provider of defaults.tftest.hcl, with its overrides: nothing is
# created, the asserts check presence and wiring (#61, M2).

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


run "the_outputs_are_what_a_root_wires" {
  command = apply

  assert {
    condition     = output.cluster_name == azurerm_kubernetes_cluster.socle.name && output.location == azurerm_resource_group.socle[0].location
    error_message = "cluster_name and location are the cluster's and its resource group's."
  }

  assert {
    condition     = output.cluster_endpoint == azurerm_kubernetes_cluster.socle.private_fqdn && output.cluster_ca_certificate == azurerm_kubernetes_cluster.socle.kube_config[0].cluster_ca_certificate
    error_message = "cluster_endpoint and cluster_ca_certificate are AKS's."
  }

  assert {
    condition     = output.oidc_issuer_url == azurerm_kubernetes_cluster.socle.oidc_issuer_url
    error_message = "oidc_issuer_url is the cluster's issuer."
  }

  assert {
    condition     = output.resource_group_name == azurerm_resource_group.socle[0].name && output.vnet_name == azurerm_virtual_network.socle[0].name && output.node_subnet_id == azurerm_subnet.node[0].id
    error_message = "resource_group_name, vnet_name and node_subnet_id name what the module created."
  }

  assert {
    condition     = output.tags.owner == var.owner && output.tags.environment == var.environment
    error_message = "tags carries the owner and the environment."
  }
}
