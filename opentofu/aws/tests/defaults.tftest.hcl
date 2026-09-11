# A consumer who sets nothing gets the recommended configuration. These runs
# assert that, and that the preconditions guarding incoherent inputs fire.
#
# Static credentials, skip_*_validation and the override below keep the plan
# offline: nothing here refreshes state or reads an existing resource.

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
  environment  = "prod"

  availability_zones = ["eu-west-3a", "eu-west-3b"]

  create_vpc = true

  kubernetes_version                   = "1.34"
  cluster_endpoint_public_access_cidrs = ["203.0.113.0/32"]
}

run "defaults_are_the_recommended_position" {
  command = plan

  assert {
    condition     = aws_eks_cluster.socle.force_update_version == false
    error_message = "force_update_version must default to false: Upgrade Insights is a pre-check, not an apply-time gate this module enforces."
  }

  assert {
    condition     = aws_eks_cluster.socle.vpc_config[0].endpoint_private_access == true
    error_message = "Private access must be on by default."
  }

  assert {
    condition     = aws_eks_cluster.socle.vpc_config[0].endpoint_public_access == true
    error_message = "Public access stays on by default — restricted by CIDR, not turned off."
  }

  assert {
    condition     = aws_eks_cluster.socle.access_config[0].authentication_mode == "API"
    error_message = "API-only auth mode: the aws-auth ConfigMap is legacy."
  }

  assert {
    condition     = length(aws_kms_key.secrets) == 1
    error_message = "A KMS key must be created by default: secrets_encryption_enabled defaults to true and no external key is supplied."
  }

  assert {
    condition     = contains(one(aws_eks_cluster.socle.encryption_config).resources, "secrets")
    error_message = "Encryption config must target Kubernetes Secrets."
  }

  assert {
    condition     = length(aws_subnet.private) == 2
    error_message = "One private subnet per AZ must be created by default."
  }

  assert {
    condition     = length(aws_subnet.public) == 2
    error_message = "One public subnet per AZ must be created by default — the private-only escape hatch does not exist."
  }

  assert {
    condition     = length(aws_nat_gateway.socle) == 2
    error_message = "One NAT Gateway per AZ must be created by default: private nodes cannot pull an image without egress."
  }

  assert {
    condition     = length(aws_vpc_endpoint.s3) == 1
    error_message = "The S3 Gateway endpoint is always on — strictly free, no reason not to have it."
  }

  assert {
    condition     = length(aws_vpc_endpoint.interface) == 5
    error_message = "All five Interface endpoints (ecr.api, ecr.dkr, sts, ec2, logs) must be standard, not optional."
  }

  assert {
    condition     = aws_iam_role.ebs_csi.name == "socle-test-ebs-csi"
    error_message = "The EBS CSI role stays even though the add-on left: the factory binds it when it installs the driver."
  }

  assert {
    condition     = aws_eks_pod_identity_association.crossplane.namespace == "crossplane-system"
    error_message = "Crossplane's default namespace must be crossplane-system."
  }

  assert {
    condition     = aws_eks_pod_identity_association.crossplane.service_account == "provider-aws"
    error_message = "Crossplane's default service account must be provider-aws."
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.crossplane) == 0
    error_message = "Crossplane must get no policies by default: the catalog does not exist yet."
  }

  assert {
    condition     = one(aws_eks_cluster.socle.upgrade_policy).support_type == "EXTENDED"
    error_message = "Support type must be set explicitly, even to AWS's own default: leaving it unset is how a cluster ends up on the 6x rate without anyone choosing it."
  }

  assert {
    condition     = aws_eks_cluster.socle.bootstrap_self_managed_addons == false
    error_message = "Self-managed VPC CNI and kube-proxy must never be installed: Socle runs Cilium."
  }

  assert {
    condition     = length(aws_eks_cluster.socle.enabled_cluster_log_types) == 5
    error_message = "All five control plane log types must be on by default — audit and authenticator are the only record of who did what."
  }

  assert {
    condition     = aws_kms_key.logs.enable_key_rotation == true
    error_message = "The log encryption key must rotate: it outlives every log group it encrypts."
  }

  assert {
    condition     = aws_cloudwatch_log_group.cluster.retention_in_days == 90
    error_message = "The control plane log group must carry a retention: the one EKS creates on its own never expires."
  }

  assert {
    condition     = length(aws_flow_log.socle) == 1
    error_message = "VPC flow logs must be on by default — the segmentation this VPC is built around is unauditable without them."
  }

  assert {
    condition     = aws_eks_cluster.socle.tags["socle-version"] == "0.1.0-dev"
    error_message = "Every billable resource must carry the socle version that created it."
  }
}

run "attaching_to_an_existing_vpc_with_matching_subnets_is_coherent" {
  command = plan

  variables {
    create_vpc         = false
    vpc_id             = "vpc-0123456789abcdef0"
    private_subnet_ids = ["subnet-priv-a", "subnet-priv-b"]
    public_subnet_ids  = ["subnet-pub-a", "subnet-pub-b"]
  }

  assert {
    condition     = length(aws_subnet.private) == 0
    error_message = "No subnets should be created when attaching to an existing VPC."
  }

  assert {
    condition     = length(aws_vpc_endpoint.interface) == 0
    error_message = "Endpoints are only managed on a VPC this module also creates."
  }
}
