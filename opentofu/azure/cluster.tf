# The cluster — docs/azure/cluster-mode.md (Standard + Node Auto-Provisioning),
# docs/azure/managed-scope.md (upgrades, add-ons, identity) and
# docs/azure/network-security.md (CNI, private cluster). An empty-shell
# control plane: Cilium, the CSI drivers and the Gateway API controller are
# factory components delivered through the socle OCI artifact, not
# provisioned by this module.

# AKS's Log Analytics workspace, for Container Insights below. This is
# unrelated to the account-level PaaS metrics decision in
# docs/azure/cloud-observability.md (which refuses Log Analytics entirely
# for SQL/Storage/Service Bus/Redis, read from outside the cluster) —
# Container Insights is a normal in-cluster AKS add-on with no other path.
resource "azurerm_log_analytics_workspace" "container_insights" {
  name                = "${var.cluster_name}-insights"
  resource_group_name = local.resource_group_name
  location            = local.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days

  tags = local.tags
}

# Managed Prometheus needs its own workspace plus a data collection rule
# routing the cluster's metrics into it — monitor_metrics on the cluster
# resource below only turns the add-on on, it carries no workspace
# reference itself.
resource "azurerm_monitor_workspace" "socle" {
  name                = "${var.cluster_name}-metrics"
  resource_group_name = local.resource_group_name
  location            = local.location

  tags = local.tags
}

resource "azurerm_monitor_data_collection_rule" "prometheus" {
  name                = "${var.cluster_name}-prometheus"
  resource_group_name = local.resource_group_name
  location            = local.location
  kind                = "Linux"

  destinations {
    monitor_account {
      monitor_account_id = azurerm_monitor_workspace.socle.id
      name               = "prometheus"
    }
  }

  data_flow {
    streams      = ["Microsoft-PrometheusMetrics"]
    destinations = ["prometheus"]
  }

  data_sources {
    prometheus_forwarder {
      streams = ["Microsoft-PrometheusMetrics"]
      name    = "prometheus-forwarder"
    }
  }

  tags = local.tags
}

resource "azurerm_monitor_data_collection_rule_association" "prometheus" {
  name                    = "${var.cluster_name}-prometheus"
  target_resource_id      = azurerm_kubernetes_cluster.socle.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.prometheus.id
}

# Two things intentionally absent from this resource:
#
# - Deployment Safeguards (Baseline/Enforce, decided in
#   docs/azure/managed-scope.md): azurerm has no attribute for it as of the
#   4.x series — grepped the provider source directly, zero hits. The
#   underlying ARM property (safeguardsProfile on the managed cluster
#   resource) has no open-source GitOps equivalent either, unlike Cilium or
#   Karpenter — it is a Microsoft-curated policy bundle reachable only
#   through Azure's own API. Getting it in would mean either the azapi
#   provider against a schema this session couldn't fully verify against
#   the raw ARM Swagger, or a manual `az aks safeguards update` step that
#   would break the checklist's "single apply, no out-of-band step" rule.
#   Left out of this empty-shell module rather than guessed at — revisit
#   once azurerm supports it natively or the azapi schema is confirmed.
#
# - Microsoft Defender for Containers: a subscription-level singleton
#   (azurerm_security_center_subscription_pricing), not a per-cluster
#   setting — it is the client's own call on their own subscription, not
#   this module's or Socle's to toggle or document. No resource, no
#   variable, nothing planned to document about it either.

# Two scanner findings are answered here rather than argued in a review.
#
# Network policy (AZU-0043) is not a choice this resource can make: azurerm
# only accepts network_policy when network_plugin is "azure" — there is no
# value to set under BYO CNI's "none". Cilium provides the real enforcement
# once the factory installs it — full L3/L4/L7, not gated behind a paid
# add-on. Argued in docs/azure/network-security.md.
#
# Disk encryption set (AZU-0067) would swap Microsoft-managed keys for a
# customer-managed one on the node OS disks. Microsoft-managed is the
# module's default posture; a CMK is a client's own compliance decision on
# their own Key Vault, the same class of call as Defender, above — not
# something to default into an empty-shell module.
#trivy:ignore:AZU-0043
#trivy:ignore:AZU-0067
resource "azurerm_kubernetes_cluster" "socle" {
  name                = var.cluster_name
  resource_group_name = local.resource_group_name
  location            = local.location
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version

  sku_tier = "Standard"

  # Already the provider's own default — AKS has required Kubernetes RBAC
  # for years, this can no longer be turned off. Declared explicitly so a
  # static scanner reading the HCL sees the same thing the API returns.
  role_based_access_control_enabled = true

  # Azure's own inline identity — Azure creates and manages it itself, no
  # separate role resource for this module to create.
  identity {
    type = "SystemAssigned"
  }

  # NAP is opt-in and explicit here, not preconfigured the way AKS
  # Automatic would bundle it — same open-source engine either way.
  node_provisioning_profile {
    mode = "Auto"
  }

  # A default node pool is structurally mandatory on this resource — AKS
  # cannot exist with zero node pools. This is the minimum AKS requires to
  # exist at all, not a Karpenter/NAP replacement: NAP
  # only ever manages the "user" node pools it provisions on demand, never
  # this "system" one. Kept as small and as tainted-for-system-only as
  # AKS allows, so nothing workload-shaped schedules here by accident.
  default_node_pool {
    name                         = "system"
    vm_size                      = var.system_node_pool_vm_size
    node_count                   = var.system_node_pool_node_count
    zones                        = var.zones
    vnet_subnet_id               = local.node_subnet_id
    only_critical_addons_enabled = true

    # AKS assigns this block its own defaults server-side regardless of
    # whether it's declared. Left unset, that produces a perpetual diff —
    # every plan sees Azure's default and proposes tearing it back out.
    # Declared explicitly, matching Azure's own default, so plan converges.
    upgrade_settings {
      max_surge = "10%"
    }
  }

  # BYO CNI: Cilium is not installed by this module. It is the first Helm
  # release of the bootstrap module, before Flux — nothing without
  # hostNetwork starts until it runs, so the catalog cannot carry it
  # (docs/catalog/cilium.md). Nodes stay NotReady until it lands. Pod IPAM
  # is entirely Cilium's own from that point on, from var.pod_cidr.
  #
  # No pod_cidr here: azurerm only allows setting it when network_plugin is
  # kubenet or network_plugin_mode is overlay — not none. Microsoft's own
  # BYO CNI CLI docs pass --pod-cidr at creation for the control plane's
  # routing to pods, but the azurerm provider's schema doesn't expose that
  # field for this mode. A real gap between the ARM API's own surface and
  # this provider version, not a decision — flagged for the same reason
  # Deployment Safeguards is, above. var.pod_cidr therefore only reaches
  # Cilium's cluster pool, through this module's output.
  #
  # outbound_type = userAssignedNATGateway: this module attaches its own
  # NAT Gateway directly to the node subnet (network.tf), not one AKS
  # creates and manages itself — this just tells AKS not to fall back to
  # its default load-balancer-based egress path on top of it.
  network_profile {
    network_plugin    = "none"
    service_cidr      = var.service_cidr
    dns_service_ip    = var.dns_service_ip
    load_balancer_sku = "standard"
    outbound_type     = "userAssignedNATGateway"
  }

  # stable, hardcoded: our own choice, grounded in AKS's own N-2
  # support-window margin, not "no alternative" — see
  # docs/azure/managed-scope.md. KubernetesOfficial, hardcoded: refusing
  # LTS by policy — a cluster hardcoded to stable is never far enough
  # behind to need it.
  automatic_upgrade_channel = "stable"
  support_plan              = "KubernetesOfficial"

  # Required, no default — see variables.tf. stable auto-triggers upgrades
  # within these windows; the node OS window is a separate schedule.
  maintenance_window_auto_upgrade {
    frequency   = var.maintenance_window_auto_upgrade.frequency
    interval    = var.maintenance_window_auto_upgrade.interval
    duration    = var.maintenance_window_auto_upgrade.duration
    day_of_week = var.maintenance_window_auto_upgrade.day_of_week
    start_time  = var.maintenance_window_auto_upgrade.start_time
    utc_offset  = var.maintenance_window_auto_upgrade.utc_offset
  }

  maintenance_window_node_os {
    frequency   = var.maintenance_window_node_os.frequency
    interval    = var.maintenance_window_node_os.interval
    duration    = var.maintenance_window_node_os.duration
    day_of_week = var.maintenance_window_node_os.day_of_week
    start_time  = var.maintenance_window_node_os.start_time
    utc_offset  = var.maintenance_window_node_os.utc_offset
  }

  # Private cluster, public FQDN disabled — nodes already sit in a private
  # subnet behind NAT, so a publicly reachable control plane would be the
  # one remaining public surface. System-managed private DNS zone: no
  # reason here to bring a custom one.
  private_cluster_enabled             = true
  private_dns_zone_id                 = "System"
  private_cluster_public_fqdn_enabled = false

  # Entra Workload ID, enabled explicitly. oidc_issuer_enabled defaults to
  # false on the 4.x provider series this module targets — set explicitly
  # rather than relying on a default that flips between provider majors.
  workload_identity_enabled = true
  oidc_issuer_enabled       = true

  # Storage CSI stays AKS-managed — no attribute to set, nothing to turn
  # on or off here.

  # Monitoring, turned on explicitly — Standard does not default to either.
  oms_agent {
    log_analytics_workspace_id      = azurerm_log_analytics_workspace.container_insights.id
    msi_auth_for_monitoring_enabled = true
  }

  monitor_metrics {}

  azure_policy_enabled = true

  tags = local.tags
}
