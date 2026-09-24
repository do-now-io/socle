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
    condition     = aws_eks_cluster.socle.access_config[0].bootstrap_cluster_creator_admin_permissions == true
    error_message = "The apply-time principal must get a cluster-admin access entry: left unset, a real apply against provider 6.x grants none at all, only EKS's own service role."
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
    condition     = aws_iam_role.cluster.name == "socle-test-cluster"
    error_message = "The cluster's service role is one of the only two roles left: EKS assumes it directly, so it cannot belong to the layer above."
  }

  assert {
    condition     = one(aws_eks_cluster.socle.upgrade_policy).support_type == "STANDARD"
    error_message = "Extended support must be impossible, not merely discouraged: AWS's own default is EXTENDED, and a cluster that enters it cannot leave until it is upgraded."
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
    condition     = aws_eks_cluster.socle.tags["socle-version"] == "0.0.0" # x-release-please-version
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

run "helm_kubernetes_is_credential_free_and_uses_the_aws_exec_plugin" {
  command = plan

  assert {
    condition     = output.helm_kubernetes.exec.command == "aws" && contains(output.helm_kubernetes.exec.args, "get-token")
    error_message = "helm_kubernetes must obtain its token at call time through aws eks get-token, never carry one."
  }
  assert {
    condition     = !can(output.helm_kubernetes.token) && !can(output.helm_kubernetes.client_key)
    error_message = "helm_kubernetes must carry no credential."
  }
}

run "cilium_operator_policy_grants_eni_ipam_and_nothing_more" {
  command = plan

  assert {
    condition     = contains(jsondecode(output.cilium_operator_policy_json).Statement[0].Action, "ec2:CreateNetworkInterface") && contains(jsondecode(output.cilium_operator_policy_json).Statement[0].Action, "ec2:AssignPrivateIpAddresses")
    error_message = "the policy must carry what Cilium's operator calls to allocate ENIs and addresses."
  }
  assert {
    condition     = alltrue([for a in jsondecode(output.cilium_operator_policy_json).Statement[0].Action : startswith(a, "ec2:")])
    error_message = "the policy must stay within EC2: the operator manages network interfaces, nothing else."
  }
}

run "a_null_input_takes_the_module_default" {
  command = plan
  variables {
    create_vpc            = null
    vpc_flow_logs_enabled = null
    log_retention_days    = null
  }

  assert {
    condition     = length(aws_vpc.socle) == 1 && length(aws_flow_log.socle) == 1
    error_message = "a root that passes an omitted optional key as null must get the module's recommended position, not a null: nullable = false is what makes that true."
  }
}

run "crossplane_gets_no_identity_unless_asked" {
  command = plan

  assert {
    condition     = length(aws_iam_role.crossplane) == 0 && length(aws_iam_policy.crossplane_boundary) == 0 && length(aws_eks_pod_identity_association.crossplane) == 0
    error_message = "crossplane defaults to null: no role, no boundary, no association — the most powerful identity in the cluster exists only when the client asks for it."
  }
  assert {
    condition     = output.crossplane_permissions_boundary_arn == null && output.crossplane_role_arn == null
    error_message = "both crossplane outputs must be null when crossplane is not set."
  }
}

run "crossplane_identity_creates_only_bounded_roles" {
  command = plan
  variables {
    crossplane = { allowed_services = ["route53"] }
  }

  # The role policy names the boundary's and the cluster's ARNs, unknown at
  # plan; pinned here so the document can be read.
  override_resource {
    target = aws_iam_policy.crossplane_boundary
    values = { arn = "arn:aws:iam::000000000000:policy/socle/socle-test/crossplane-boundary" }
  }
  override_resource {
    target = aws_eks_cluster.socle
    values = {
      arn                   = "arn:aws:eks:eu-west-3:000000000000:cluster/socle-test"
      certificate_authority = [{ data = "Y2E=" }]
    }
  }

  assert {
    condition     = aws_eks_pod_identity_association.crossplane[0].namespace == "crossplane-system" && aws_eks_pod_identity_association.crossplane[0].service_account == "provider-aws"
    error_message = "the association must name crossplane-system/provider-aws, the ServiceAccount the socle artifact fixes for every AWS provider pod."
  }
  assert {
    condition     = jsondecode(aws_iam_role.crossplane[0].assume_role_policy).Statement[0].Principal.Service == "pods.eks.amazonaws.com"
    error_message = "the Crossplane role must be trusted by EKS Pod Identity, not IRSA."
  }
  assert {
    condition     = aws_iam_policy.crossplane_boundary[0].path == "/socle/socle-test/" && jsondecode(aws_iam_policy.crossplane_boundary[0].policy).Statement[0].Action == "route53:*" && length(jsondecode(aws_iam_policy.crossplane_boundary[0].policy).Statement) == 2
    error_message = "the boundary must live under /socle/<cluster>/ and allow exactly the listed services, plus its deny."
  }
  assert {
    condition     = one([for st in jsondecode(aws_iam_policy.crossplane_boundary[0].policy).Statement : st.Effect == "Deny" && contains(st.Action, "iam:*") && contains(st.Action, "sts:*") if st.Sid == "NeverIdentityNorAccount"])
    error_message = "the boundary must always deny identity and account services."
  }
  assert {
    condition     = alltrue([for st in jsondecode(aws_iam_role_policy.crossplane[0].policy).Statement : st.Resource == "arn:aws:iam::000000000000:role/socle/socle-test/*" if st.Sid != "PodIdentityAssociationsOnThisCluster"])
    error_message = "every IAM statement of the Crossplane identity must be scoped to roles under /socle/<cluster>/."
  }
  assert {
    condition     = one([for st in jsondecode(aws_iam_role_policy.crossplane[0].policy).Statement : contains(st.Action, "iam:CreateRole") if st.Sid == "CreateAndWriteRolesUnderTheBoundary"]) && one([for st in jsondecode(aws_iam_role_policy.crossplane[0].policy).Statement : keys(st.Condition.StringEquals) if st.Sid == "CreateAndWriteRolesUnderTheBoundary"]) == ["iam:PermissionsBoundary"]
    error_message = "CreateRole must be conditioned on the permissions boundary."
  }
  assert {
    condition     = !anytrue(flatten([for st in jsondecode(aws_iam_role_policy.crossplane[0].policy).Statement : [for a in flatten([st.Action]) : contains(["iam:AttachRolePolicy", "iam:DeleteRolePermissionsBoundary", "iam:CreatePolicy", "iam:CreatePolicyVersion", "iam:*", "*"], a)]]))
    error_message = "the Crossplane identity must not attach managed policies, remove a boundary or write policies."
  }
}

run "crossplane_without_a_service_gets_a_boundary_that_grants_nothing" {
  command = plan
  variables {
    crossplane = {}
  }

  assert {
    condition     = alltrue([for st in jsondecode(aws_iam_policy.crossplane_boundary[0].policy).Statement : st.Effect == "Deny"])
    error_message = "with no service allowed, the boundary must allow nothing: a role Crossplane creates then grants nothing."
  }
}
