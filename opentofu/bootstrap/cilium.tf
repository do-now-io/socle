# Cilium — the CNI, where the cloud provides none. docs/catalog/cilium.md.
#
# GKE (Dataplane V2) and Kapsule (cni = "cilium") operate Cilium themselves:
# nothing to install, and the `cilium` variable is refused there. EKS and AKS
# are created by the foundations with no CNI at all (bootstrap_self_managed_
# addons = false, network_plugin = "none"), and that settles where Cilium
# lives: not in the catalog. Nothing without hostNetwork can start on a
# CNI-less cluster — not flux-operator, not the Flux controllers — so the
# catalog, which Flux renders, cannot deliver the thing Flux needs to run.
# Cilium's agent, operator and Envoy all run hostNetwork, so Helm installs
# them on that cluster, before flux-operator. Helm is already the applier
# here (docs/flux-catalog.md §3); this adds releases, not a mechanism.
#
# Three releases, in order, all `count`ed on the cloud:
#   0. gateway-api-crds — the standard channel, vendored at the exact version
#      Cilium documents. Cilium reads them at start-up and disables its
#      Gateway API controller when they are absent, so they come first.
#   1. cilium — ENI mode on aws, BYOCNI on azure, kube-proxy replacement on
#      both with the API endpoint the foundations output.
#   2. coredns — aws only. The same flag that removed the VPC CNI removed
#      CoreDNS, and Flux's source-controller resolves ghcr.io. The EKS
#      managed add-on cannot do this job: with no CNI its pods never
#      schedule, the add-on sits DEGRADED, and the aws provider waits for
#      ACTIVE until it times out — inside the foundations module, which
#      applies before this one. AKS ships CoreDNS as a system pod under BYO
#      CNI, Pending until Cilium runs.
# flux-operator then depends on all three.
#
# The chart versions are pinned here, not variables: they move with the
# socle release, like the operator's. The client's surface is `var.cilium`:
# on/off, Hubble, Gateway API. Everything else is the position argued in the
# design note.

locals {
  # Chart versions. The Gateway API version is the one this Cilium minor
  # documents; .github/scripts/check-gateway-api-crds.sh proves the vendored
  # file is that release, byte for byte.
  cilium_chart_version  = "1.20.2"
  coredns_chart_version = "1.47.1"
  gateway_api_version   = "1.6.1"

  # The client's surface, and its schema — the same convention as the
  # catalog: the defaults ARE the attribute names a client may set.
  cilium_schema = {
    enabled     = true
    hubble      = false
    gateway_api = true
  }
  cilium = merge(local.cilium_schema, var.cilium)

  # Where the socle runs Cilium: the two clouds whose foundations create a
  # cluster with no CNI. `enabled = false` is the escape hatch for a cluster
  # that brings its own — the e2e k3s behind floci's EKS is one.
  cilium_clouds    = ["aws", "azure"]
  cilium_installed = contains(local.cilium_clouds, var.cloud) && local.cilium.enabled

  # kube-proxy replacement needs the API server's address, not a ClusterIP —
  # there is no kube-proxy to program one. The foundations output the
  # endpoint as EKS returns it (https://host) or as AKS does (a bare FQDN);
  # both reduce to host and port here. Unknown at plan on a first apply,
  # like every value the cluster produces.
  api_endpoint = try(regex("^(?:https://)?(?P<host>[^/:]+)(?::(?P<port>[0-9]+))?/?$", var.cluster_network.api_endpoint), { host = null, port = null })
  api_host     = local.api_endpoint.host
  api_port     = tonumber(coalesce(local.api_endpoint.port, "443"))

  cilium_values_common = {
    kubeProxyReplacement = true
    k8sServiceHost       = local.api_host
    k8sServicePort       = local.api_port

    # A ConfigMap change restarts the agents; otherwise it waits for the
    # next node rotation and the fleet runs two configurations meanwhile.
    rollOutCiliumPods = true

    # Requests only. The agent's memory follows the number of endpoints and
    # identities; a limit would be a guess that kills the CNI when wrong.
    resources = { requests = { cpu = "100m", memory = "256Mi" } }
    envoy     = { resources = { requests = { cpu = "50m", memory = "128Mi" } } }
    operator = {
      # One operator. It is a control loop, not a datapath: its outage delays
      # IP allocation for new pods and nothing else. Two would be the chart's
      # default, sized for clusters larger than the ones this module starts.
      replicas    = 1
      rollOutPods = true
      resources   = { requests = { cpu = "50m", memory = "128Mi" } }
    }

    # Hubble's flow observability is always on in the agent; relay and UI —
    # the parts that cost a Deployment each — are the client's call.
    hubble = {
      relay = { enabled = local.cilium.hubble }
      ui    = { enabled = local.cilium.hubble }
    }

    # Cilium serves the `cilium` GatewayClass. Needs kube-proxy replacement
    # (set) and the CRDs (release 0).
    gatewayAPI = { enabled = local.cilium.gateway_api }
  }

  # What only one cloud needs. Measured against the 1.20.2 chart: eni.enabled
  # alone yields ipam=eni, routing-mode=native, endpoint routes, masquerade
  # off — pods carry VPC addresses and egress through the NAT Gateway — and
  # ENIs in the node's own subnet, the operator's default. aksbyocni.enabled
  # alone yields cluster-pool IPAM over VXLAN; the pool is the foundations'
  # pod_cidr, because the chart's own default, 10.0.0.0/8, contains the VNet.
  cilium_values_cloud = {
    aws = {
      eni = { enabled = true }
    }
    azure = {
      aksbyocni = { enabled = true }
      ipam      = { operator = { clusterPoolIPv4PodCIDRList = compact([try(var.cluster_network.pod_cidr, null)]) } }
    }
  }
}

# 0. The Gateway API CRDs, standard channel, from the vendored chart. Before
# Cilium: its operator looks for them once, at start-up. Present whenever
# Cilium is, whatever the gateway_api toggle says — the API is the same on
# every cloud the socle runs, only the implementation differs, and a Gateway
# API module that also shipped them here would fight this release for the
# same objects.
resource "helm_release" "gateway_api_crds" {
  count = local.cilium_installed ? 1 : 0

  name  = "gateway-api-crds"
  chart = "${path.module}/gateway-api-crds"

  namespace = "kube-system"

  wait    = true
  timeout = var.helm_timeout_seconds
}

# 1. Cilium. kube-system, where every CNI lives and where the chart's own
# defaults and RBAC assume it is.
resource "helm_release" "cilium" {
  count = local.cilium_installed ? 1 : 0

  name       = "cilium"
  repository = "oci://quay.io/cilium/charts"
  chart      = "cilium"
  version    = local.cilium_chart_version

  namespace = "kube-system"

  # Returns once the agent runs on every node and the operator is Ready —
  # which is what "the cluster has a network" means. Needs at least one
  # node, as does everything after it.
  wait    = true
  timeout = var.helm_timeout_seconds

  values = [yamlencode(merge(local.cilium_values_common, local.cilium_values_cloud[var.cloud]))]

  depends_on = [helm_release.gateway_api_crds]
}

# 2. CoreDNS, on aws only, after Cilium — its pods need a network. The
# Service takes the address every EKS node's kubelet is told to use,
# `.10` of the service range, under the name and label the managed add-on
# would have given it, so nothing downstream can tell the difference.
resource "helm_release" "coredns" {
  count = var.cloud == "aws" && local.cilium_installed ? 1 : 0

  name       = "coredns"
  repository = "oci://ghcr.io/coredns/charts"
  chart      = "coredns"
  version    = local.coredns_chart_version

  namespace = "kube-system"

  wait    = true
  timeout = var.helm_timeout_seconds

  values = [yamlencode({
    fullnameOverride = "coredns"
    service = {
      name      = "kube-dns"
      clusterIP = cidrhost(var.cluster_network.service_cidr, 10)
    }
    k8sAppLabelOverride = "kube-dns"
    priorityClassName   = "system-cluster-critical"

    # Two replicas on different nodes when the cluster has them; the EKS
    # add-on's own sizing.
    replicaCount = 2
    resources = {
      requests = { cpu = "100m", memory = "70Mi" }
      limits   = { memory = "170Mi" }
    }
    podDisruptionBudget = { maxUnavailable = 1 }
    affinity = {
      podAntiAffinity = {
        preferredDuringSchedulingIgnoredDuringExecution = [{
          weight = 100
          podAffinityTerm = {
            topologyKey   = "kubernetes.io/hostname"
            labelSelector = { matchLabels = { "k8s-app" = "kube-dns" } }
          }
        }]
      }
    }
    tolerations = [{ key = "CriticalAddonsOnly", operator = "Exists" }]
  })]

  depends_on = [helm_release.cilium]
}
