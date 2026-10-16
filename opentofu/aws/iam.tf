# Identities — docs/decisions/aws.md, AWS-03 (Pod Identity, not IRSA) and
# AWS-18 (Crossplane's identity and its permissions boundary).

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

# Four roles live in this module: the cluster's service role above, which
# EKS itself assumes; the bootstrap nodes' role in nodes.tf; the flow logs'
# delivery role in network.tf; and, when var.crossplane is set, Crossplane's
# role below, the one workload identity written here. Every other workload
# identity is declared by the catalog module that needs it, or, for the CSI
# drivers, beside their add-on in opentofu/bootstrap/eks_addons.tf.

# What Cilium's operator calls in ENI mode. It runs hostNetwork, so the
# identity it runs under is its node's: the bootstrap nodes' role carries this
# inline (nodes.tf). A document, not an aws_iam_policy, so the same text can
# go to any other node role the operator may land on. The list is Cilium's
# own (docs.cilium.io, ENI IPAM, "Required privileges"), plus DescribeTags for
# its ENI garbage collection.
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

# A catalog module declares its identity as a CloudAccess claim the
# crossplane module turns into a role — docs/catalog/crossplane.md.

# --- crossplane — docs/catalog/crossplane.md ----------------------------------
#
# The one workload identity the socle cannot make for itself: Crossplane
# creates every other one, and something has to create Crossplane's. Both
# halves are known before the cluster has a node — the socle artifact runs
# every AWS provider pod as crossplane-system/provider-aws (a ServiceAccount
# the crossplane module creates, never one Crossplane owns: #80) — so the role
# and its Pod Identity association are written here, and only when asked.
# Credentials reach the pods through the Pod Identity Agent add-on, which the
# bootstrap module installs with the other managed add-ons, before Flux
# (opentofu/bootstrap/eks_addons.tf, docs/decisions/aws.md, AWS-02).
#
# An identity that can create IAM roles is the most powerful thing in the
# cluster. What bounds it, statement by statement below:
# - roles only under /socle/<cluster>/, and only created carrying the
#   permissions boundary this module writes — so no role Crossplane makes can
#   ever do more than the boundary, whatever inline policy it is given;
# - no way to remove or swap that boundary, no managed-policy attachment, no
#   policy creation, no access to any role outside the path — its own
#   included, which lives at /;
# - PassRole to EKS Pod Identity only, associations on this cluster only;
# - buckets, queues and EventBridge rules under the cluster's name prefix
#   only, the resources a module owns beside its role.
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
  crossplane_role_path     = "/socle/${var.cluster_name}/"
  crossplane_boundary_name = "${var.cluster_name}-crossplane-boundary"
  crossplane_roles_arn     = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/socle/${var.cluster_name}/*"

  # What a module's role may never do: create or change identities, assume
  # other roles, reach the organisation or the account settings.
  crossplane_denied_services = ["iam", "sts", "organizations", "account", "sso", "identitystore"]

  # The one exception to "never iam", and only once the client allows ec2: a
  # role that may launch instances may launch them as the socle's node role
  # — the bootstrap nodes' (nodes.tf), the only role an instance of this
  # cluster ever runs as — and read the instance profiles that carry it.
  # Karpenter's controller is that role (docs/catalog/karpenter.md): EC2
  # refuses RunInstances with an instance profile unless the caller may pass
  # its role, and Karpenter checks the profile it is given before using it.
  # Nothing else of IAM: no other role to pass, no profile to create or to
  # change, so no module can make an instance of more than the nodes already
  # are. docs/decisions/aws.md, AWS-21.
  crossplane_node_role_exception = contains(try(var.crossplane.allowed_services, []), "ec2")
  crossplane_node_role_arn       = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.cluster_name}-bootstrap-node"
  crossplane_instance_profiles   = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*"

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
      [for st in [
        {
          Sid       = "PassTheNodeRoleToEc2Only"
          Effect    = "Allow"
          Action    = "iam:PassRole"
          Resource  = local.crossplane_node_role_arn
          Condition = { StringEquals = { "iam:PassedToService" = "ec2.amazonaws.com" } }
        },
        {
          Sid      = "ReadInstanceProfiles"
          Effect   = "Allow"
          Action   = ["iam:GetInstanceProfile", "iam:ListInstanceProfiles"]
          Resource = local.crossplane_instance_profiles
        },
      ] : st if local.crossplane_node_role_exception],
      [{
        Sid      = "NeverIdentityNorAccount"
        Effect   = "Deny"
        Action   = [for svc in local.crossplane_denied_services : "${svc}:*" if !(local.crossplane_node_role_exception && svc == "iam")]
        Resource = "*"
      }],
      # With the exception, iam is denied on everything but the node role and
      # the instance profiles; on those, only the two statements above allow
      # anything, so every other IAM action stays refused there too.
      [for st in [{
        Sid         = "NeverIamBeyondTheNodeRole"
        Effect      = "Deny"
        Action      = "iam:*"
        NotResource = [local.crossplane_node_role_arn, local.crossplane_instance_profiles]
      }] : st if local.crossplane_node_role_exception],
    )
  })
}

resource "aws_iam_policy" "crossplane_boundary" {
  count = var.crossplane == null ? 0 : 1

  # Named after the cluster, not only placed under its path: IAM policy
  # names are unique per account whatever the path, so a bare
  # crossplane-boundary collides with the next cluster in the same account.
  name        = local.crossplane_boundary_name
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
        # A read, not a write: IAM evaluates it against whatever ARN the
        # request lets it construct, and for a role that does not exist yet
        # that is account and name only — it has no path to check against,
        # since nothing has ever created this role to tell it one. Scoped to
        # the path, this statement would deny the read-before-create every
        # provider does first, on every role it has not made yet. A read
        # carries no capability the boundary is meant to stop, so it is
        # scoped to the account instead, not the path.
        Sid    = "ReadAnyRoleInTheAccount"
        Effect = "Allow"
        Action = [
          "iam:GetRole",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:ListInstanceProfilesForRole",
          "iam:ListRoleTags",
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*"
      },
      {
        Sid    = "TagAndDeleteRolesInThePath"
        Effect = "Allow"
        Action = [
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
      {
        # A module's own bucket, as a module's own role: under a prefix the
        # cluster owns (docs/catalog/crossplane.md §3, docs/catalog/velero.md
        # §8). Create it, read its configuration, write its versioning,
        # encryption, public access block, lifecycle and tags — the bucket
        # ARN only, so no object is ever read or written. No delete of any
        # kind: Crossplane can never remove a bucket of backups, whatever a
        # managed resource's deletionPolicy says.
        Sid    = "ManageBucketsUnderTheClusterPrefix"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:ListBucket",
          "s3:GetBucket*",
          "s3:GetAccelerateConfiguration",
          "s3:GetEncryptionConfiguration",
          "s3:GetLifecycleConfiguration",
          "s3:GetReplicationConfiguration",
          "s3:PutBucketTagging",
          "s3:PutBucketVersioning",
          "s3:PutBucketPublicAccessBlock",
          "s3:PutEncryptionConfiguration",
          "s3:PutLifecycleConfiguration",
          # The provider reads and writes a bucket's tags through S3 Control
          # (ListTagsForResource), not GetBucketTagging — measured on floci.
          "s3:ListTagsForResource",
          "s3:TagResource",
          "s3:UntagResource",
        ]
        Resource = "arn:aws:s3:::${var.cluster_name}-*"
      },
      {
        # A module's own queue, under the cluster's prefix: Karpenter's
        # interruption queue (docs/catalog/karpenter.md). Create it, read and
        # write its attributes — its access policy among them, which is what
        # lets EventBridge deliver to it — tag it, delete it. A queue holds
        # notices minutes old, nothing to keep: it goes with the module.
        Sid    = "ManageQueuesUnderTheClusterPrefix"
        Effect = "Allow"
        Action = [
          "sqs:CreateQueue",
          "sqs:DeleteQueue",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:SetQueueAttributes",
          "sqs:ListQueueTags",
          "sqs:TagQueue",
          "sqs:UntagQueue",
        ]
        Resource = "arn:aws:sqs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:${var.cluster_name}-*"
      },
      {
        # A module's own EventBridge rules on the default bus, under the
        # cluster's prefix, and their targets: the EC2 and AWS Health events
        # Karpenter reads from its queue. A target needs no role to reach a
        # queue — the queue's policy admits events.amazonaws.com — so no
        # PassRole here.
        Sid    = "ManageEventRulesUnderTheClusterPrefix"
        Effect = "Allow"
        Action = [
          "events:PutRule",
          "events:DescribeRule",
          "events:DeleteRule",
          "events:EnableRule",
          "events:DisableRule",
          "events:PutTargets",
          "events:RemoveTargets",
          "events:ListTargetsByRule",
          "events:ListTagsForResource",
          "events:TagResource",
          "events:UntagResource",
        ]
        Resource = "arn:aws:events:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:rule/${var.cluster_name}-*"
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
