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
# What remains are the three roles this module's own resources cannot do
# without: the cluster's service role, which EKS itself assumes, the
# bootstrap nodes' role in nodes.tf, and the flow logs' delivery role in
# network.tf.

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
