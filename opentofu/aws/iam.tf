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
