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

# EBS CSI driver's own identity, via Pod Identity — not IRSA. The trust
# policy targets pods.eks.amazonaws.com, not an OIDC-federated principal;
# sts:TagSession alongside sts:AssumeRole is Pod Identity's own
# requirement, not an IRSA leftover.

resource "aws_iam_role" "ebs_csi" {
  name = "${var.cluster_name}-ebs-csi"

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

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# Crossplane's own identity, via Pod Identity — verified to support it,
# same as the LB controller and both CSI drivers. A standalone
# aws_eks_pod_identity_association, not the aws_eks_addon-embedded block
# used for ebs_csi above: Crossplane is not an EKS-managed add-on.

resource "aws_iam_role" "crossplane" {
  name = "${var.cluster_name}-crossplane"

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

resource "aws_eks_pod_identity_association" "crossplane" {
  cluster_name    = aws_eks_cluster.socle.name
  namespace       = var.crossplane_service_account_namespace
  service_account = var.crossplane_service_account_name
  role_arn        = aws_iam_role.crossplane.arn

  depends_on = [aws_eks_addon.pod_identity_agent]
}

# Empty by default. The catalog does not exist yet, so any list of
# policies written today would be a guess presented as a recommendation.
resource "aws_iam_role_policy_attachment" "crossplane" {
  for_each = toset(var.crossplane_policy_arns)

  role       = aws_iam_role.crossplane.name
  policy_arn = each.value
}
