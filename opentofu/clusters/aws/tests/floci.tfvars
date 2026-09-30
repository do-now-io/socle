# Fixtures for an apply against floci (a real k3s behind an emulated EKS).
# socle_version and cosign_identity are supplied on the command line: they
# name the pre-release the current commit published.
aws = {
  region                               = "eu-west-3"
  cluster_name                         = "socle-e2e"
  owner                                = "platform"
  environment                          = "dev"
  availability_zones                   = ["eu-west-3a", "eu-west-3b"]
  cluster_endpoint_public_access_cidrs = ["203.0.113.0/32"]
  kubernetes_version                   = "1.34"
}

kube = {
  # Client values merged over the socle's defaults, asserted by e2e-aws-root:
  # a key the socle leaves unset (accounts.e2e, EXPECT_ARGOCD_ACCOUNT) and one
  # the socle sets — server memory request, 64Mi in the socle's document —
  # where the client must win (EXPECT_ARGOCD_SERVER_MEMORY) while the socle's
  # sibling cpu request survives the deep merge.
  argocd = {
    values = {
      configs = { cm = { "accounts.e2e" = "apiKey" } }
      server  = { resources = { requests = { memory = "96Mi" } } }
    }
  }
  # The same proof for victoria_metrics, asserted by e2e-aws-root: a flag the
  # socle sets — -storage.maxHourlySeries, 100000 in its document — where the
  # client must win (EXPECT_VM_MAX_HOURLY_SERIES) while the socle's sibling
  # flags survive the merge.
  victoria_metrics = {
    values = {
      server = { extraArgs = { "storage.maxHourlySeries" = "50000" } }
    }
  }
  # And for otel_agent: the socle requests 128Mi for the DaemonSet's
  # container; the client's 160Mi must win (EXPECT_OTEL_AGENT_MEMORY) while
  # the socle's cpu request and memory limit survive the merge.
  otel_agent = {
    values = {
      resources = { requests = { memory = "160Mi" } }
    }
  }
  # And for otel_gateway: 320Mi over the socle's 128Mi
  # (EXPECT_OTEL_GATEWAY_MEMORY), its 100m and 1Gi limit intact.
  otel_gateway = {
    values = {
      resources = { requests = { memory = "320Mi" } }
    }
  }
  # And for grafana: 320Mi over the socle's 256Mi (EXPECT_GRAFANA_MEMORY).
  grafana = {
    values = {
      resources = { requests = { memory = "320Mi" } }
    }
  }
  # And for victoria_logs: 160Mi over the socle's 128Mi
  # (EXPECT_VICTORIA_LOGS_MEMORY), its 50m intact.
  victoria_logs = {
    values = {
      server = { resources = { requests = { memory = "160Mi" } } }
    }
  }
  hello = {
    replicas = 1
  }
}

# floci's EKS is a k3s with its own CNI (flannel), kube-proxy and CoreDNS. The
# production default installs Cilium and CoreDNS before Flux, which here would
# fight the CNI already in place; this is the one case the toggle exists for.
cilium = {
  enabled = false
}

# floci records EKS add-ons as metadata only, and not before a release later
# than the one CI pins (1.5.34 has no add-on API at all): its k3s runs no
# add-on workload either way. The e2e proves the catalog, not AWS's packaging.
eks_addons = {
  pod_identity_agent = false
  ebs_csi            = false
}
