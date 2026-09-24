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
