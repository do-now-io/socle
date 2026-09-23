# Identities — docs/aws/eks-managed-scope.md (Pod Identity, not IRSA).

# The cluster's own service role — not a research decision, a structural
# requirement of EKS itself: the control plane assumes this role to manage
# ENIs, security groups and load balancers on the consumer's behalf.

resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# No identity for the in-cluster Crossplane provider, and none for anything
# else the layer above installs. Such a role is only half an identity: the
# other half is a Pod Identity association naming a Kubernetes service account
# that does not exist until the plugins are deployed. That association is built
# where its service account is, in a second step, and the role goes with it.
#
# What remains here are the two roles this module's own resources cannot do
# without: the cluster's service role, which EKS itself assumes, and the flow
# logs' delivery role in network.tf.

# No identity for the in-cluster Crossplane provider, and none for anything
# else the layer above installs. Such a role is only half an identity: the
# other half is a Pod Identity association naming a Kubernetes service account
# that does not exist until the plugins are deployed. That association is built
# where its service account is, in a second step, and the role goes with it.
#
# What remains here are the two roles this module's own resources cannot do
# without: the cluster's service role, which EKS itself assumes, and the flow
# logs' delivery role in network.tf.

# What Cilium's operator calls in ENI mode, as a policy document rather than a
# role: the bootstrap module installs Cilium, but the identity it runs under is
# the node's until Pod Identity exists (its agent is an add-on installed once
# compute does), and nodes are the factory's. Whoever creates the node role
# attaches this. A document, not an aws_iam_policy: nothing billable, nothing
# to toggle. The list is Cilium's own (docs.cilium.io, ENI IPAM, "Required
# privileges"), plus DescribeTags for its ENI garbage collection.
data "aws_iam_policy_document" "cilium_operator" {
  statement {
    sid = "CiliumEniIpam"
    actions = [
      "ec2:AssignPrivateIpAddresses",
      "ec2:AttachNetworkInterface",
      "ec2:CreateNetworkInterface",
      "ec2:CreateTags",
      "ec2:DeleteNetworkInterface",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeRouteTables",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeTags",
      "ec2:DescribeVpcs",
      "ec2:ModifyNetworkInterfaceAttribute",
    ]
    # EC2's network-interface actions take no resource-level scoping that
    # would survive ENIs being created on the fly; AWS's own VPC CNI policy
    # (AmazonEKS_CNI_Policy) grants the same actions on "*".
    resources = ["*"]
  }
}

# What remains here, besides the Crossplane identity below, are the two roles
# this module's own resources cannot do without: the cluster's service role,
# which EKS itself assumes, and the flow logs' delivery role in network.tf.
# Every other workload identity is declared by the catalog module that needs
# it, as a CloudAccess claim the crossplane module turns into a role —
# docs/catalog/crossplane.md.

# --- crossplane — docs/catalog/crossplane.md ----------------------------------
#
# The one workload identity the socle cannot make for itself: Crossplane
# creates every other one, and something has to create Crossplane's. Both
# halves are known before the cluster has a node — the socle artifact runs
# every AWS provider pod as crossplane-system/provider-aws (a fixed
# serviceAccountTemplate name in its DeploymentRuntimeConfig) — so the role
# and its Pod Identity association are written here, and only when asked.
# Credentials reach the pods through the Pod Identity Agent add-on, which the
# factory installs with the other managed add-ons (docs/aws/eks-managed-scope.md
# §1).
#
# An identity that can create IAM roles is the most powerful thing in the
# cluster. What bounds it, statement by statement below:
# - roles only under /socle/<cluster>/, and only created carrying the
#   permissions boundary this module writes — so no role Crossplane makes can
#   ever do more than the boundary, whatever inline policy it is given;
# - no way to remove or swap that boundary, no managed-policy attachment, no
#   policy creation, no access to any role outside the path — its own
#   included, which lives at /;
# - PassRole to EKS Pod Identity only, associations on this cluster only.
# What it cannot bound: a role's trust policy. IAM has no condition key on
# the document, so a compromised Crossplane could create a role, within the
# boundary, that another principal may assume. The boundary is the answer —
# it is what makes such a role worth no more than the services it allows.
#
# The boundary is an allowlist of services the client writes
# (crossplane.allowed_services), empty by default — a role Crossplane creates
# then grants nothing. It names services, not resources: which zone, which
# bucket, is each module's own role policy, so a new module never needs a
# change here, only, when it uses a new service, one word in the client's
# tfvars. Identity and account services are denied whatever the list says:
# no role Crossplane creates can mint identities, chain into other roles or
# touch the organisation.

locals {
  crossplane_role_path = "/socle/${var.cluster_name}/"
  crossplane_roles_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/socle/${var.cluster_name}/*"

  # What a module's role may never do: create or change identities, assume
  # other roles, reach the organisation or the account settings.
  crossplane_denied_services = ["iam", "sts", "organizations", "account", "sso", "identitystore"]

  # The ceiling of every role Crossplane creates. The deny is always there,
  # which also keeps an empty allowlist a valid document.
  crossplane_boundary_policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [for svc in try(var.crossplane.allowed_services, []) : {
        Sid      = "Allow${join("", [for w in split("-", svc) : title(w)])}"
        Effect   = "Allow"
        Action   = "${svc}:*"
        Resource = "*"
      }],
      [{
        Sid      = "NeverIdentityNorAccount"
        Effect   = "Deny"
        Action   = [for svc in local.crossplane_denied_services : "${svc}:*"]
        Resource = "*"
      }],
    )
  })
}

resource "aws_iam_policy" "crossplane_boundary" {
  count = var.crossplane == null ? 0 : 1

  name        = "crossplane-boundary"
  path        = local.crossplane_role_path
  description = "Permissions boundary of every role the ${var.cluster_name} socle's Crossplane creates."

  policy = local.crossplane_boundary_policy

  tags = local.tags
}

resource "aws_iam_role" "crossplane" {
  count = var.crossplane == null ? 0 : 1

  name = "${var.cluster_name}-crossplane"

  # The Pod Identity trust: the EKS pods principal, AssumeRole plus
  # TagSession, which the agent uses to stamp the session with the cluster,
  # namespace and ServiceAccount.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "crossplane" {
  count = var.crossplane == null ? 0 : 1

  name = "create-bounded-roles"
  role = aws_iam_role.crossplane[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Creating a role, setting its boundary, and writing its inline
        # policy or trust are allowed only when the boundary is ours:
        # iam:PermissionsBoundary is evaluated on each of these calls.
        Sid    = "CreateAndWriteRolesUnderTheBoundary"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:PutRolePermissionsBoundary",
          "iam:PutRolePolicy",
          "iam:UpdateAssumeRolePolicy",
        ]
        Resource  = local.crossplane_roles_arn
        Condition = { StringEquals = { "iam:PermissionsBoundary" = aws_iam_policy.crossplane_boundary[0].arn } }
      },
      {
        Sid    = "ReadTagAndDeleteRolesInThePath"
        Effect = "Allow"
        Action = [
          "iam:GetRole",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:ListInstanceProfilesForRole",
          "iam:ListRoleTags",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:UpdateRole",
          "iam:UpdateRoleDescription",
          "iam:DeleteRolePolicy",
          "iam:DeleteRole",
        ]
        Resource = local.crossplane_roles_arn
      },
      {
        Sid       = "PassRolesToPodIdentityOnly"
        Effect    = "Allow"
        Action    = "iam:PassRole"
        Resource  = local.crossplane_roles_arn
        Condition = { StringEquals = { "iam:PassedToService" = "pods.eks.amazonaws.com" } }
      },
      {
        Sid    = "PodIdentityAssociationsOnThisCluster"
        Effect = "Allow"
        Action = [
          "eks:CreatePodIdentityAssociation",
          "eks:DescribePodIdentityAssociation",
          "eks:UpdatePodIdentityAssociation",
          "eks:DeletePodIdentityAssociation",
          "eks:ListPodIdentityAssociations",
          "eks:TagResource",
          "eks:UntagResource",
          "eks:ListTagsForResource",
        ]
        Resource = [
          aws_eks_cluster.socle.arn,
          "arn:aws:eks:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:podidentityassociation/${var.cluster_name}/*",
        ]
      },
    ]
  })
}

resource "aws_eks_pod_identity_association" "crossplane" {
  count = var.crossplane == null ? 0 : 1

  cluster_name    = aws_eks_cluster.socle.name
  namespace       = "crossplane-system"
  service_account = "provider-aws"
  role_arn        = aws_iam_role.crossplane[0].arn

  tags = local.tags
}
