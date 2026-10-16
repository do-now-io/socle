# What the root adds over its two modules: the values it derives for the
# catalog from the foundations, the warning when Crossplane has no identity,
# and what it passes through. Static credentials, skip_*_validation and the
# overrides keep every run offline, as in opentofu/aws's own tests: a plan
# creates every resource, so it reads none. helm is mocked.

provider "aws" {
  region                      = "eu-west-3"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_region_validation      = true
}

# The one data source each module reads from the account: the boundary's ARN
# and the add-ons' roles name it.
override_data {
  target = module.foundations.data.aws_caller_identity.current
  values = { account_id = "000000000000" }
}

override_data {
  target = module.socle.data.aws_caller_identity.current
  values = { account_id = "000000000000" }
}

# The shared Gateways' zone, looked up by name when gateway_certificate is set.
override_data {
  target = module.foundations.data.aws_route53_zone.gateway
  values = { zone_id = "Z0123456789ABCDEFGHIJ" }
}

mock_provider "helm" {}

# kube and cilium are reset here: tests/example.auto.tfvars, the example a
# client copies, is loaded for every file in this directory.
variables {
  socle_version = "0.0.0-e2e.abc1234"
  kube          = {}
  cilium        = {}
  aws = {
    region                               = "eu-west-3"
    cluster_name                         = "socle-test"
    owner                                = "platform"
    environment                          = "prod"
    kubernetes_version                   = "1.34"
    availability_zones                   = ["eu-west-3a", "eu-west-3b"]
    cluster_endpoint_public_access_cidrs = ["203.0.113.0/32"]
  }
}

run "socle_version_reaches_the_artifact_and_the_inputs" {
  command = plan

  assert {
    condition     = output.cilium.installed == true
    error_message = "on aws the bootstrap installs Cilium by default."
  }

  assert {
    condition     = output.artifact.tag == "0.0.0-e2e.abc1234" && output.inputs.socle.version == "0.0.0-e2e.abc1234"
    error_message = "socle_version reaches the artifact the cluster pulls and the inputs the catalog renders from."
  }

  assert {
    condition     = output.cluster_name == "socle-test" && output.inputs.cloud == "aws" && output.inputs.cluster.name == "socle-test" && output.inputs.cluster.region == "eu-west-3"
    error_message = "the catalog's cloud, cluster and region are the root's."
  }
}

# The endpoint exists once EKS has created the cluster: read from the
# foundations' outputs, given here as a real apply returns them. The
# override needs an attached VPC: a created one is indexed in the
# foundations' locals, which an overridden module never creates.
run "the_endpoint_is_the_foundations" {
  command = plan

  variables {
    aws = {
      region                               = "eu-west-3"
      cluster_name                         = "socle-test"
      owner                                = "platform"
      environment                          = "prod"
      kubernetes_version                   = "1.34"
      availability_zones                   = ["eu-west-3a", "eu-west-3b"]
      cluster_endpoint_public_access_cidrs = ["203.0.113.0/32"]
      create_vpc                           = false
      vpc_id                               = "vpc-0123456789abcdef0"
      private_subnet_ids                   = ["subnet-priv-a", "subnet-priv-b"]
      public_subnet_ids                    = ["subnet-pub-a", "subnet-pub-b"]
    }
  }

  override_module {
    target = module.foundations
    outputs = {
      cluster_name                        = "socle-test"
      cluster_endpoint                    = "https://0123456789ABCDEF.gr7.eu-west-3.eks.amazonaws.com"
      service_cidr                        = "172.20.0.0/16"
      gateway_certificate_arn             = null
      crossplane_permissions_boundary_arn = null
      bootstrap_node_group                = { name = "bootstrap", node_count = 2, instance_types = ["t4g.xlarge"], capacity_type = "SPOT" }
      helm_kubernetes = {
        host                   = "https://0123456789ABCDEF.gr7.eu-west-3.eks.amazonaws.com"
        cluster_ca_certificate = "-----BEGIN CERTIFICATE-----"
        exec = {
          api_version = "client.authentication.k8s.io/v1beta1"
          command     = "aws"
          args        = ["eks", "get-token", "--cluster-name", "socle-test"]
        }
      }
    }
  }

  assert {
    condition     = output.cluster_endpoint == "https://0123456789ABCDEF.gr7.eu-west-3.eks.amazonaws.com"
    error_message = "cluster_endpoint is the foundations'."
  }
}

run "without_crossplane_the_boundary_is_empty" {
  command = plan

  assert {
    condition     = output.inputs.modules.crossplane.permissions_boundary == ""
    error_message = "with aws.crossplane null, no boundary reaches the catalog."
  }
}

run "the_boundary_is_added_and_the_clients_keys_kept" {
  command = plan

  variables {
    aws = {
      region                               = "eu-west-3"
      cluster_name                         = "socle-test"
      owner                                = "platform"
      environment                          = "prod"
      kubernetes_version                   = "1.34"
      availability_zones                   = ["eu-west-3a", "eu-west-3b"]
      cluster_endpoint_public_access_cidrs = ["203.0.113.0/32"]
      crossplane                           = { allowed_services = ["route53"] }
    }
    kube = {
      crossplane = { enabled = true, values = { replicas = 2 } }
      hello      = { replicas = 3 }
    }
  }

  assert {
    condition     = output.inputs.modules.crossplane.permissions_boundary == "arn:aws:iam::000000000000:policy/socle/socle-test/socle-test-crossplane-boundary"
    error_message = "with aws.crossplane set, the foundations' boundary is kube.crossplane.permissions_boundary."
  }

  assert {
    condition     = output.inputs.modules.crossplane.enabled == true && output.inputs.modules.crossplane.values.replicas == 2 && output.inputs.modules.hello.replicas == 3
    error_message = "the client's keys, in crossplane and elsewhere, are kept beside the derived boundary."
  }

  assert {
    condition     = output.inputs.modules.external_dns.enabled == false
    error_message = "without gateway_certificate, external_dns is not derived on."
  }
}

run "a_boundary_the_client_wrote_wins" {
  command = plan

  variables {
    aws = {
      region                               = "eu-west-3"
      cluster_name                         = "socle-test"
      owner                                = "platform"
      environment                          = "prod"
      kubernetes_version                   = "1.34"
      availability_zones                   = ["eu-west-3a", "eu-west-3b"]
      cluster_endpoint_public_access_cidrs = ["203.0.113.0/32"]
      crossplane                           = {}
    }
    kube = { crossplane = { enabled = true, permissions_boundary = "arn:aws:iam::000000000000:policy/client-boundary" } }
  }

  assert {
    condition     = output.inputs.modules.crossplane.permissions_boundary == "arn:aws:iam::000000000000:policy/client-boundary"
    error_message = "a boundary the client wrote under kube.crossplane wins over the derived one."
  }
}

run "external_dns_follows_the_certificate" {
  command = plan

  variables {
    aws = {
      region                               = "eu-west-3"
      cluster_name                         = "socle-test"
      owner                                = "platform"
      environment                          = "prod"
      kubernetes_version                   = "1.34"
      availability_zones                   = ["eu-west-3a", "eu-west-3b"]
      cluster_endpoint_public_access_cidrs = ["203.0.113.0/32"]
      crossplane                           = { allowed_services = ["route53"] }
      gateway_certificate                  = { domain = "sandbox.kubemulus.com" }
    }
    kube = { crossplane = { enabled = true } }
  }

  assert {
    condition     = output.inputs.modules.external_dns.enabled == true && tolist(output.inputs.modules.external_dns.domain_filters) == tolist(["sandbox.kubemulus.com"])
    error_message = "with the certificate, Crossplane on and route53 allowed, external_dns is on, filtered to the certificate's domain."
  }
}

run "external_dns_stays_off_without_route53" {
  command = plan

  variables {
    aws = {
      region                               = "eu-west-3"
      cluster_name                         = "socle-test"
      owner                                = "platform"
      environment                          = "prod"
      kubernetes_version                   = "1.34"
      availability_zones                   = ["eu-west-3a", "eu-west-3b"]
      cluster_endpoint_public_access_cidrs = ["203.0.113.0/32"]
      crossplane                           = { allowed_services = ["sqs"] }
      gateway_certificate                  = { domain = "sandbox.kubemulus.com" }
    }
    kube = { crossplane = { enabled = true } }
  }

  assert {
    condition     = output.inputs.modules.external_dns.enabled == false
    error_message = "without route53 in Crossplane's allowed services, nothing could bind external-dns's role: it stays off."
  }
}

run "cilium_off_reaches_the_bootstrap" {
  command = plan

  variables {
    cilium = { enabled = false }
  }

  assert {
    condition     = output.cilium.installed == false && output.cilium.chart_version == null
    error_message = "cilium = { enabled = false } must reach the bootstrap module: no Cilium release."
  }
}

run "crossplane_without_identity_warns" {
  command = plan

  variables {
    kube = { crossplane = { enabled = true } }
  }

  expect_failures = [check.crossplane_has_an_identity]
}

run "socle_version_refuses_what_is_not_semver" {
  command = plan

  variables {
    socle_version = "latest"
  }

  expect_failures = [var.socle_version]
}
