# One failing-input case per validation block. A validation nobody tested
# is a validation nobody knows works.

mock_provider "azurerm" {}

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
  environment  = "dev"
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

# --- Identity of the deployment --------------------------------------------

run "cluster_name_must_look_like_an_aks_cluster_name" {
  command = plan

  variables {
    cluster_name = "Socle Test!"
  }

  expect_failures = [var.cluster_name]
}

# --- Network ----------------------------------------------------------------

run "vnet_name_and_create_vnet_true_is_incoherent" {
  command = plan

  variables {
    create_vnet = true
    vnet_name   = "existing-vnet"
  }

  expect_failures = [var.vnet_name]
}

run "node_subnet_id_and_create_vnet_true_is_incoherent" {
  command = plan

  variables {
    create_vnet    = true
    node_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/existing/providers/Microsoft.Network/virtualNetworks/existing-vnet/subnets/nodes"
  }

  expect_failures = [var.node_subnet_id]
}

run "neither_creating_nor_attaching_a_vnet_is_incoherent" {
  command = plan

  variables {
    create_vnet    = false
    vnet_name      = null
    node_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/existing/providers/Microsoft.Network/virtualNetworks/existing-vnet/subnets/nodes"
  }

  expect_failures = [var.vnet_name]
}

run "creating_a_vnet_without_a_nat_gateway_is_incoherent" {
  command = plan

  variables {
    create_vnet        = true
    create_nat_gateway = false
  }

  expect_failures = [var.create_nat_gateway]
}

# --- Cluster ------------------------------------------------------------

run "kubernetes_version_rejects_a_patch_component" {
  command = plan

  variables {
    kubernetes_version = "1.34.2"
  }

  expect_failures = [var.kubernetes_version]
}

run "pod_cidr_rejects_a_bare_address" {
  command = plan

  variables {
    pod_cidr = "10.244.0.0"
  }

  expect_failures = [var.pod_cidr]
}

run "system_node_pool_node_count_rejects_zero" {
  command = plan

  variables {
    system_node_pool_node_count = 0
  }

  expect_failures = [var.system_node_pool_node_count]
}

run "log_retention_days_rejects_a_period_log_analytics_does_not_accept" {
  command = plan

  variables {
    log_retention_days = 45
  }

  expect_failures = [var.log_retention_days]
}

run "maintenance_window_auto_upgrade_duration_below_four_hours_is_rejected" {
  command = plan

  variables {
    maintenance_window_auto_upgrade = {
      frequency = "Weekly"
      interval  = 1
      duration  = 2
    }
  }

  expect_failures = [var.maintenance_window_auto_upgrade]
}

run "maintenance_window_node_os_duration_above_24_hours_is_rejected" {
  command = plan

  variables {
    maintenance_window_node_os = {
      frequency = "Weekly"
      interval  = 1
      duration  = 30
    }
  }

  expect_failures = [var.maintenance_window_node_os]
}
