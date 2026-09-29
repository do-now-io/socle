# EKS-managed add-ons — docs/aws/eks-managed-scope.md §1.
#
# The Pod Identity Agent, EBS CSI and EFS CSI stay EKS-managed add-ons: AWS
# packages them, the socle pins them and triggers every upgrade. They cannot
# be created with the cluster — the foundations stop at "nothing that needs a
# pod to run" (opentofu/aws/cluster.tf) — so they are created here, once the
# nodes exist and, for the two drivers, once Cilium and CoreDNS run:
#
#   1. eks-pod-identity-agent — a hostNetwork DaemonSet that tolerates every
#      taint, so it needs the nodes but not the network. It is what hands
#      credentials to every Pod Identity association: without it Crossplane's
#      AWS providers hang on 169.254.170.23 without logging a line (#48).
#      flux-operator waits for it, so nothing the catalog renders ever starts
#      on a cluster that cannot give it an identity.
#   2. aws-ebs-csi-driver — its controller is a Deployment, like CoreDNS: it
#      needs Cilium for a pod address and CoreDNS to resolve the EC2 API.
#   3. aws-efs-csi-driver — the same, and off by default: RWX only, a
#      catalog option rather than a default (§1).
#
# Each driver's identity is written here, beside the add-on that runs its
# pods, and bound through the add-on's own pod_identity_association — the
# layer that installs a pod owns its identity. Neither role lives under
# /socle/<cluster>/: that path is Crossplane's, and nothing Crossplane can
# rewrite may hold the storage drivers' permissions.
#
# The versions are pinned, never most_recent: AWS never upgrades an add-on by
# itself, so the trigger is the socle release, like the chart versions in
# cilium.tf. Each is one AWS lists as compatible with every Kubernetes
# version the socle supports.

locals {
  eks_addon_versions = {
    pod_identity_agent = "v1.4.0-eksbuild.2"
    ebs_csi            = "v1.66.0-eksbuild.1"
    efs_csi            = "v3.4.2-eksbuild.1"
  }

  # The client's surface, and its schema — the defaults ARE the attribute
  # names a client may set.
  eks_addons_schema = {
    pod_identity_agent = true
    ebs_csi            = true
    efs_csi            = false
  }
  eks_addons = merge(local.eks_addons_schema, var.eks_addons)

  # Only EKS has them. Elsewhere `eks_addons` is refused, and nothing here
  # is created.
  eks_addon_installed = { for a, on in local.eks_addons : a => var.cloud == "aws" && on }

  # The foundations' own tag set, minus what only the client's root knows.
  aws_tags = {
    owner           = var.owner
    environment     = var.environment
    "socle-version" = local.socle_version
  }

  # The Pod Identity trust: the EKS pods principal, AssumeRole plus
  # TagSession, which the agent uses to stamp the session with the cluster,
  # namespace and ServiceAccount. The same document as Crossplane's role in
  # the foundations.
  pod_identity_trust = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  no_node_addon_message = "The cluster has no schedulable node (schedulable_nodes = 0), so the EKS add-ons cannot start and AWS reports them DEGRADED. On aws the foundations' bootstrap_node_count sets it; it must be at least 1."
}

# 1. The Pod Identity Agent. After Cilium only because the nodes are, and
# because the node group this module waits for through schedulable_nodes is
# ACTIVE only once Cilium runs on it.
resource "aws_eks_addon" "pod_identity_agent" {
  count = local.eks_addon_installed.pod_identity_agent ? 1 : 0

  cluster_name  = var.cluster_name
  addon_name    = "eks-pod-identity-agent"
  addon_version = local.eks_addon_versions.pod_identity_agent

  # The socle's configuration wins over whatever is in the cluster: the
  # add-on is created on a cluster that never ran it, and every upgrade is
  # the socle's.
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.aws_tags

  lifecycle {
    precondition {
      condition     = var.schedulable_nodes != 0
      error_message = local.no_node_addon_message
    }
  }

  depends_on = [helm_release.cilium]
}

# 2. EBS CSI, and its identity. AWS's managed policy, the driver's own list;
# its write actions are conditioned on the tags the driver puts on the
# volumes and snapshots it creates.
resource "aws_iam_role" "ebs_csi" {
  count = local.eks_addon_installed.ebs_csi ? 1 : 0

  name = "${var.cluster_name}-ebs-csi"
  # Written out: not /socle/<cluster>/, the path Crossplane may rewrite.
  path               = "/"
  assume_role_policy = local.pod_identity_trust

  tags = local.aws_tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  count = local.eks_addon_installed.ebs_csi ? 1 : 0

  role       = aws_iam_role.ebs_csi[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_addon" "ebs_csi" {
  count = local.eks_addon_installed.ebs_csi ? 1 : 0

  cluster_name  = var.cluster_name
  addon_name    = "aws-ebs-csi-driver"
  addon_version = local.eks_addon_versions.ebs_csi

  # Only the controller calls the EC2 API; the node plugin mounts what the
  # controller attached, with no AWS credential.
  pod_identity_association {
    service_account = "ebs-csi-controller-sa"
    role_arn        = aws_iam_role.ebs_csi[0].arn
  }

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.aws_tags

  lifecycle {
    precondition {
      condition     = var.schedulable_nodes != 0
      error_message = local.no_node_addon_message
    }
  }

  # The policy before the pods: a controller that starts with a role and no
  # permissions fails its first calls and backs off.
  depends_on = [
    helm_release.cilium,
    helm_release.coredns,
    aws_eks_addon.pod_identity_agent,
    aws_iam_role_policy_attachment.ebs_csi,
  ]
}

# 3. EFS CSI, and its identity. The same shape as EBS's.
resource "aws_iam_role" "efs_csi" {
  count = local.eks_addon_installed.efs_csi ? 1 : 0

  name = "${var.cluster_name}-efs-csi"
  # Written out: not /socle/<cluster>/, the path Crossplane may rewrite.
  path               = "/"
  assume_role_policy = local.pod_identity_trust

  tags = local.aws_tags
}

resource "aws_iam_role_policy_attachment" "efs_csi" {
  count = local.eks_addon_installed.efs_csi ? 1 : 0

  role       = aws_iam_role.efs_csi[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
}

resource "aws_eks_addon" "efs_csi" {
  count = local.eks_addon_installed.efs_csi ? 1 : 0

  cluster_name  = var.cluster_name
  addon_name    = "aws-efs-csi-driver"
  addon_version = local.eks_addon_versions.efs_csi

  # The controller creates and deletes access points; the node plugin mounts
  # through efs-utils and needs a credential only for S3 Files, which the
  # socle does not offer.
  pod_identity_association {
    service_account = "efs-csi-controller-sa"
    role_arn        = aws_iam_role.efs_csi[0].arn
  }

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.aws_tags

  lifecycle {
    precondition {
      condition     = var.schedulable_nodes != 0
      error_message = local.no_node_addon_message
    }
  }

  depends_on = [
    helm_release.cilium,
    helm_release.coredns,
    aws_eks_addon.pod_identity_agent,
    aws_iam_role_policy_attachment.efs_csi,
  ]
}
