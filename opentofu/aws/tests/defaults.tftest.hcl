# A consumer who sets nothing gets the recommended configuration. These runs
# assert that, and that the preconditions guarding incoherent inputs fire.
#
# Static credentials and skip_*_validation keep the plan offline: nothing
# here refreshes state or reads an existing resource, so no API call is
# made.

provider "aws" {
  region                      = "eu-west-3"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_region_validation      = true
}

variables {
  cluster_name = "socle-test"
  owner        = "platform"
  environment  = "prod"

  availability_zones = ["eu-west-3a", "eu-west-3b"]

  create_vpc = true

  kubernetes_version                   = "1.34"
  cluster_endpoint_public_access_cidrs = ["203.0.113.0/32"]

  coredns_addon_version            = "v1.11.4-eksbuild.10"
  ebs_csi_addon_version            = "v1.44.0-eksbuild.1"
  pod_identity_agent_addon_version = "v1.3.4-eksbuild.1"
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
    condition     = length(aws_eks_addon.efs_csi) == 0
    error_message = "EFS CSI must stay off by default — catalog option."
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

run "efs_csi_lands_when_enabled_with_a_version" {
  command = plan

  variables {
    efs_csi_addon_enabled = true
    efs_csi_addon_version = "v2.1.9-eksbuild.1"
  }

  assert {
    condition     = length(aws_eks_addon.efs_csi) == 1
    error_message = "EFS CSI must be created once explicitly enabled with a version."
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
