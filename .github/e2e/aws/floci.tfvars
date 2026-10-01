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
  # Client values merged over the socle's defaults, the way a client writes
  # them: a key the socle leaves unset (accounts.e2e) and one the socle sets
  # (server memory request, 64Mi in the socle's document). The root job
  # applies them; the precedence itself is proven on the fixture root by
  # oci/catalog/argocd/tests/e2e, through a patch of the same inputs.
  argocd = {
    values = {
      configs = { cm = { "accounts.e2e" = "apiKey" } }
      server  = { resources = { requests = { memory = "96Mi" } } }
      # ECR Public throttles GitHub-hosted runners (429): see floci/main.tf.
      redis = { image = { repository = "docker.io/library/redis" } }
    }
  }
  # The same for the monitoring stack, each on a key the socle itself sets:
  # a flag of victoria_metrics (-storage.maxHourlySeries, 100000 in its
  # document) and a memory request of each collector, Grafana and
  # VictoriaLogs. Applied here as a client would; proven on the fixture root
  # by each module's tests/e2e, through a patch of the same inputs.
  victoria_metrics = {
    values = {
      server = { extraArgs = { "storage.maxHourlySeries" = "50000" } }
    }
  }
  otel_agent = {
    values = {
      resources = { requests = { memory = "160Mi" } }
    }
  }
  otel_gateway = {
    values = {
      resources = { requests = { memory = "320Mi" } }
    }
  }
  grafana = {
    values = {
      resources = { requests = { memory = "320Mi" } }
    }
  }
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

# floci 2.1.0 has no add-on API (CreateAddon answers "Unknown operation",
# measured 2026-10-01; nightly records them as metadata only), and its k3s
# runs no add-on workload either way. The e2e proves the catalog, not AWS's
# packaging.
eks_addons = {
  pod_identity_agent = false
  ebs_csi            = false
}
