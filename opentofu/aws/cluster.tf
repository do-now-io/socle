# The cluster — docs/aws/eks-cluster-mode.md (EKS Standard, no Auto Mode)
# and docs/aws/eks-managed-scope.md (add-ons, version policy, Upgrade
# Insights). An empty-shell control plane: Karpenter, Cilium, CSI drivers
# and the load balancer controller are factory components delivered
# through the socle OCI artifact, not provisioned by this module.
#
# Standard mode is the absence of a choice, not a variable: this resource
# has no compute_config/storage_config blocks (those are what Auto Mode
# would set), so it is EKS Standard by construction.

# EKS writes control plane logs to this exact name whether or not the group
# exists. Creating it here is what puts a retention on it: the group EKS
# creates on its own never expires, and nobody notices until the bill does.
resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.logs.arn

  tags = local.tags
}

# One key for both log groups this module creates — the control plane's, just
# below, and the VPC flow logs' in network.tf. CloudWatch Logs already encrypts
# at rest with an AWS-owned key; this moves custody of that key to the account
# that owns the logs, which is what an audit trail of who-did-what to the API
# server warrants. Same price as the Secrets key above it, for the same reason.
#
# AWS advises a key per log group; both of these belong to one cluster, so a
# second key would split nothing — the blast radius of losing either is that
# same cluster. The policy is AWS's own account-scoped form, narrowed to
# log groups.
resource "aws_kms_key" "logs" {
  description         = "Encryption for ${var.cluster_name} log groups."
  enable_key_rotation = true

  # CloudWatch Logs cannot use a key it is not named in, and a key whose policy
  # omits the account root is unmanageable — both statements are required.
  # The condition narrows the grant to this account's log groups instead of
  # every log group the service handles.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountRootKeepsControl"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "CloudWatchLogsUsesTheKey"
        Effect    = "Allow"
        Principal = { Service = "logs.${data.aws_region.current.region}.amazonaws.com" }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*",
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:*"
          }
        }
      },
    ]
  })

  tags = local.tags
}

# Secrets encryption's own key, only when the consumer does not bring one.
resource "aws_kms_key" "secrets" {
  count = var.secrets_encryption_enabled && var.secrets_encryption_kms_key_arn == null ? 1 : 0

  description         = "Envelope encryption for ${var.cluster_name} Kubernetes Secrets."
  enable_key_rotation = true
  tags                = local.tags
}

# Two Trivy checks are ignored on this resource, and only these two.
#
# A public API endpoint (AWS-0040) is the decision, not an oversight: private
# access is on as well, and the public half is what the socle's own automation
# and Kargo pipelines reach the cluster through. Making it private-only would
# move that access problem into a bastion or a VPN this module does not own.
#
# Reaching it from a public CIDR (AWS-0041) is the same decision seen from the
# other side. Trivy flags any public CIDR, not just an open one; the CIDR list
# is required with no default and a validation block rejects 0.0.0.0/0, which
# is the part that actually matters.
#
# Both are argued in docs/aws/eks-network-security.md.
#trivy:ignore:AVD-AWS-0040
#trivy:ignore:AVD-AWS-0041
resource "aws_eks_cluster" "socle" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  # No self-managed VPC CNI, kube-proxy or CoreDNS installed at creation.
  # Socle runs Cilium, so the first two would exist only to be removed, and
  # CoreDNS arrives later as a pinned managed add-on installed by the factory.
  bootstrap_self_managed_addons = false

  # Shipped to the log group below, which is created first so that its
  # retention applies from the first line. Left to EKS, the group is created
  # implicitly and never expires.
  enabled_cluster_log_types = var.cluster_log_types

  # Upgrade Insights is a mandatory pre-check run explicitly by the pipeline
  # (list-insights), not an apply-time gate this resource can enforce on its
  # own — AWS's own blocking of update-cluster-version on ERROR findings is
  # currently rolled back.
  force_update_version = var.force_update_version

  # What happens at the end of standard support. Left unset, AWS picks
  # EXTENDED and a lapsed cluster quietly costs six times its control plane
  # rate — see cluster_support_type.
  upgrade_policy {
    support_type = var.cluster_support_type
  }

  vpc_config {
    subnet_ids = concat(local.private_subnet_ids, local.public_subnet_ids)

    # Public access restricted by CIDR, private access on — not full
    # private-only. AWS's own recommended pattern for this case; neither
    # half is a toggle.
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.cluster_endpoint_public_access_cidrs
  }

  # API-only: the aws-auth ConfigMap is legacy. The apply-time principal
  # keeps its default cluster-admin access entry (bootstrap_cluster_creator
  # _admin_permissions is left at its true default) — enough to bootstrap
  # Flux, nothing this module has to manage explicitly.
  access_config {
    authentication_mode = "API"
  }

  dynamic "encryption_config" {
    for_each = var.secrets_encryption_enabled ? [1] : []

    content {
      resources = ["secrets"]

      provider {
        key_arn = coalesce(var.secrets_encryption_kms_key_arn, try(aws_kms_key.secrets[0].arn, null))
      }
    }
  }

  tags = local.tags

  depends_on = [
    aws_iam_role_policy_attachment.cluster,
    aws_cloudwatch_log_group.cluster,
  ]
}

# No aws_eks_addon here, and that is the module's boundary rather than an
# omission. CoreDNS and the EBS CSI controller are Deployments; on a cluster
# with no nodes their pods cannot schedule, the add-on reports DEGRADED and
# the apply fails. The Pod Identity Agent and the EFS CSI driver leave for the
# same reason rather than because they would individually break: the rule is
# that this module provisions nothing that needs a pod to run.
#
# All four stay EKS-managed add-ons — that decision is unchanged. They are
# installed by the factory, once compute exists, at versions the socle
# pipeline pins. What stays here is what they bind to: the roles in iam.tf.
