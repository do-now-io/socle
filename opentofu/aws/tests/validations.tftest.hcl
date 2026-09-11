# One failing-input case per validation block. A validation nobody tested
# is a validation nobody knows works.
#
# Static credentials, skip_*_validation and the override below keep these runs
# credential-free: variable validation fires before the plan graph, but the
# provider still has to be configurable, and the plan still resolves data
# sources.

provider "aws" {
  region                      = "eu-west-3"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_region_validation      = true
}

# data.aws_caller_identity is the one data source in this module that calls an
# API: the log encryption key's policy names the account root, and a key policy
# that omits it is unmanageable. Stubbed rather than reached, so these runs stay
# credential-free. data.aws_region resolves from provider config and needs none.
override_data {
  target = data.aws_caller_identity.current
  values = {
    account_id = "000000000000"
  }
}

variables {
  cluster_name = "socle-test"
  owner        = "platform"
  environment  = "dev"

  availability_zones = ["eu-west-3a", "eu-west-3b"]

  create_vpc = true

  kubernetes_version                   = "1.34"
  cluster_endpoint_public_access_cidrs = ["203.0.113.0/32"]
}

# --- Identity of the deployment --------------------------------------------

run "cluster_name_must_look_like_an_eks_cluster_name" {
  command = plan

  variables {
    cluster_name = "Socle_Test!"
  }

  expect_failures = [var.cluster_name]
}

# --- Network ----------------------------------------------------------------

run "vpc_id_and_create_vpc_true_is_incoherent" {
  command = plan

  variables {
    create_vpc = true
    vpc_id     = "vpc-0123456789abcdef0"
  }

  expect_failures = [var.vpc_id]
}

run "neither_creating_nor_attaching_a_vpc_is_incoherent" {
  command = plan

  variables {
    create_vpc         = false
    vpc_id             = null
    private_subnet_ids = ["subnet-priv-a", "subnet-priv-b"]
    public_subnet_ids  = ["subnet-pub-a", "subnet-pub-b"]
  }

  expect_failures = [var.vpc_id]
}

run "attaching_an_existing_vpc_needs_matching_subnet_counts" {
  command = plan

  variables {
    create_vpc         = false
    vpc_id             = "vpc-0123456789abcdef0"
    private_subnet_ids = ["subnet-priv-a"]
    public_subnet_ids  = ["subnet-pub-a", "subnet-pub-b"]
  }

  expect_failures = [var.private_subnet_ids]
}

run "creating_a_vpc_without_a_nat_gateway_is_incoherent" {
  command = plan

  variables {
    create_vpc         = true
    create_nat_gateway = false
  }

  expect_failures = [var.create_nat_gateway]
}

run "fewer_than_two_availability_zones_is_rejected" {
  command = plan

  variables {
    availability_zones = ["eu-west-3a"]
  }

  expect_failures = [var.availability_zones]
}

run "public_access_cidrs_cannot_include_the_open_internet" {
  command = plan

  variables {
    cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.cluster_endpoint_public_access_cidrs]
}

run "cluster_log_types_rejects_a_stream_eks_does_not_publish" {
  command = plan

  variables {
    cluster_log_types = ["api", "kubelet"]
  }

  expect_failures = [var.cluster_log_types]
}

run "log_retention_days_rejects_a_period_cloudwatch_does_not_accept" {
  command = plan

  variables {
    log_retention_days = 45
  }

  expect_failures = [var.log_retention_days]
}

# --- Add-ons and identity ----------------------------------------------------

run "cluster_support_type_rejects_anything_but_the_two_eks_values" {
  command = plan

  variables {
    cluster_support_type = "extended"
  }

  expect_failures = [var.cluster_support_type]
}

run "kubernetes_version_rejects_a_patch_component" {
  command = plan

  variables {
    kubernetes_version = "1.34.2"
  }

  expect_failures = [var.kubernetes_version]
}

run "crossplane_policy_arns_must_be_iam_policy_arns" {
  command = plan

  variables {
    crossplane_policy_arns = ["AmazonS3ReadOnlyAccess"]
  }

  expect_failures = [var.crossplane_policy_arns]
}
