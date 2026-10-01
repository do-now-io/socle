socle_version = "0.1.0-alpha.9"

aws = {
  region       = "eu-west-3"
  cluster_name = "acme-demo"

  owner                                = "platform"
  environment                          = "dev"
  kubernetes_version                   = "1.34"
  availability_zones                   = ["eu-west-3a", "eu-west-3b"]
  cluster_endpoint_public_access_cidrs = ["86.194.169.184/32", "82.67.41.182/32"]
  crossplane                           = { allowed_services = ["route53"] }
  gateway_certificate                  = { domain = "sandbox.kubemulus.com" }
}

kube = {
  hello = { replicas = 2 }

  crossplane       = { enabled = true }
  external_dns     = { policy = "sync" }
  argocd           = { domain = "argocd.sandbox.kubemulus.com", gateway = "public" }
  grafana          = { domain = "grafana.sandbox.kubemulus.com", gateway = "public" }
  victoria_metrics = { storage_size = "" }
  victoria_logs    = { storage_size = "" }
}
