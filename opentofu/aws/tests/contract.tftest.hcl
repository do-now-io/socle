# The outputs, as the cluster root and the bootstrap module read them. A plan
# leaves most of them unknown, so these runs apply against mocked providers:
# nothing is created, every computed attribute is a placeholder the mock
# invents. The asserts check presence and shape, the wiring between an input
# and its output, never a placeholder's format (#61, M2).

mock_provider "aws" {
  # The data sources the module reads, with values a real account returns:
  # the policy documents are JSON the module's own outputs decode, the region
  # what the provider resolved.
  mock_data "aws_region" {
    defaults = {
      region = "eu-west-3"
      name   = "eu-west-3"
    }
  }
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "000000000000"
    }
  }
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"ec2:CreateNetworkInterface\"],\"Resource\":\"*\"}]}"
    }
  }
  mock_data "aws_route53_zone" {
    defaults = {
      zone_id = "Z0123456789ABCDEFGHIJ"
    }
  }
  # Every ARN the module passes to another resource is validated as one:
  # the mock's random strings are not.
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::000000000000:role/socle/mock"
    }
  }
  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::000000000000:policy/socle/mock"
    }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:eu-west-3:000000000000:log-group:mock"
    }
  }
  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:eu-west-3:000000000000:key/00000000-0000-0000-0000-000000000000"
    }
  }
  mock_resource "aws_acm_certificate" {
    defaults = {
      arn = "arn:aws:acm:eu-west-3:000000000000:certificate/00000000-0000-0000-0000-000000000000"
    }
  }
  mock_resource "aws_eks_node_group" {
    defaults = {
      arn = "arn:aws:eks:eu-west-3:000000000000:nodegroup/socle-test/bootstrap/mock"
    }
  }
  mock_resource "aws_eks_pod_identity_association" {
    defaults = {
      arn = "arn:aws:eks:eu-west-3:000000000000:podidentityassociation/socle-test/a-mock"
    }
  }
  # And every id the provider checks the prefix of.
  mock_resource "aws_launch_template" {
    defaults = {
      id = "lt-0123456789abcdef0"
    }
  }
  mock_resource "aws_vpc" {
    defaults = {
      id = "vpc-0123456789abcdef0"
    }
  }
  mock_resource "aws_subnet" {
    defaults = {
      id = "subnet-0123456789abcdef0"
    }
  }
  mock_resource "aws_security_group" {
    defaults = {
      id = "sg-0123456789abcdef0"
    }
  }
  mock_resource "aws_internet_gateway" {
    defaults = {
      id = "igw-0123456789abcdef0"
    }
  }
  mock_resource "aws_nat_gateway" {
    defaults = {
      id = "nat-0123456789abcdef0"
    }
  }
  mock_resource "aws_eip" {
    defaults = {
      id = "eipalloc-0123456789abcdef0"
    }
  }
  mock_resource "aws_route_table" {
    defaults = {
      id = "rtb-0123456789abcdef0"
    }
  }
  mock_resource "aws_vpc_endpoint" {
    defaults = {
      id = "vpce-0123456789abcdef0"
    }
  }
  # EKS reports its endpoint, its CA and its OIDC issuer once the cluster
  # exists: given as a real cluster gives them. The service range is a
  # computed block a mock leaves empty: asserted to be the cluster's, null
  # here as on floci.
  mock_resource "aws_eks_cluster" {
    defaults = {
      arn      = "arn:aws:eks:eu-west-3:000000000000:cluster/socle-test"
      endpoint = "https://0123456789ABCDEF.gr7.eu-west-3.eks.amazonaws.com"
      certificate_authority = [{
        data = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCg=="
      }]
      identity = [{
        oidc = [{
          issuer = "https://oidc.eks.eu-west-3.amazonaws.com/id/0123456789ABCDEF"
        }]
      }]
    }
  }
}

variables {
  cluster_name = "socle-test"
  owner        = "platform"
  environment  = "prod"

  availability_zones = ["eu-west-3a", "eu-west-3b"]

  create_vpc = true

  kubernetes_version                   = "1.34"
  cluster_endpoint_public_access_cidrs = ["203.0.113.0/32"]
}

run "the_cluster_outputs_are_what_a_root_wires" {
  command = apply

  assert {
    condition     = output.cluster_name == "socle-test" && output.region == "eu-west-3"
    error_message = "cluster_name and region are the cluster's and the provider's."
  }

  assert {
    condition     = output.cluster_endpoint == "https://0123456789ABCDEF.gr7.eu-west-3.eks.amazonaws.com" && output.helm_kubernetes.host == output.cluster_endpoint
    error_message = "cluster_endpoint is EKS's, and helm_kubernetes connects to it."
  }

  assert {
    condition     = output.cluster_ca_certificate == "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCg==" && output.helm_kubernetes.cluster_ca_certificate == base64decode(output.cluster_ca_certificate)
    error_message = "cluster_ca_certificate is EKS's, base64; helm_kubernetes carries it decoded."
  }

  assert {
    condition     = output.service_cidr == try(aws_eks_cluster.socle.kubernetes_network_config[0].service_ipv4_cidr, null)
    error_message = "service_cidr is the range EKS reports, which the bootstrap module gives CoreDNS its .10 from."
  }

  assert {
    condition     = output.oidc_issuer_url == "https://oidc.eks.eu-west-3.amazonaws.com/id/0123456789ABCDEF"
    error_message = "oidc_issuer_url is the cluster's issuer."
  }
}

run "the_network_outputs_name_what_the_module_created" {
  command = apply

  assert {
    condition     = output.vpc_id == aws_vpc.socle[0].id
    error_message = "vpc_id is the VPC the module created when create_vpc is true."
  }

  assert {
    condition     = length(output.private_subnet_ids) == 2 && length(output.public_subnet_ids) == 2
    error_message = "One private and one public subnet per availability zone."
  }

  assert {
    condition     = output.tags.owner == "platform" && output.tags.environment == "prod" && output.tags["socle-version"] != ""
    error_message = "tags carries the owner and the environment every billable resource is tagged with."
  }
}

run "an_attached_vpc_is_passed_through" {
  command = apply

  variables {
    create_vpc         = false
    vpc_id             = "vpc-0123456789abcdef0"
    private_subnet_ids = ["subnet-priv-a", "subnet-priv-b"]
    public_subnet_ids  = ["subnet-pub-a", "subnet-pub-b"]
  }

  assert {
    condition     = output.vpc_id == "vpc-0123456789abcdef0" && output.private_subnet_ids == tolist(["subnet-priv-a", "subnet-priv-b"]) && output.public_subnet_ids == tolist(["subnet-pub-a", "subnet-pub-b"])
    error_message = "An attached VPC and its subnets come back out as given."
  }
}
