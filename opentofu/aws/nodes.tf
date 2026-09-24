# The bootstrap node group: the one piece of compute this module owns.
#
# It carries what the socle installs before anything else can run — Cilium's
# operator, CoreDNS, the Flux operator and controllers — and later Karpenter,
# which provisions every other node. It is not the cluster's capacity: it
# does not autoscale, and Karpenter scales nothing here. A cluster with no
# node is not a cluster, whatever runs on top, so this is not a change the
# catalog asked for. docs/catalog/cilium.md §2.
#
# Its nodes boot with no CNI and stay NotReady until Cilium's agent runs, and
# a managed node group is ACTIVE only once its nodes are Ready. So the
# bootstrap module's Cilium release must not wait for this group: the root
# applies it beside the group, and only what needs a scheduled pod — CoreDNS
# first — waits for it (opentofu/clusters/aws).

locals {
  # The AMI follows the instance types' architecture: Graviton families carry
  # a "g" among the letters after their generation (t4g, m7gd, c7gn). Read
  # from the names rather than DescribeInstanceTypes, which keeps the plan
  # free of an API call. The variable refuses a list that mixes the two.
  bootstrap_node_arm64 = can(regex("^[a-z]+[0-9]+[a-z]*g[a-z]*\\.", var.bootstrap_node_instance_types[0]))
}

# The nodes' role. What the kubelet needs to join, what containerd needs to
# pull from ECR (EKS's own images live there), and what Cilium's operator needs in ENI mode: it runs
# hostNetwork on these nodes and reaches this role through instance
# metadata. No AmazonEKS_CNI_Policy: that is the VPC CNI's, and this cluster
# does not run it. EKS creates the access entry itself.
resource "aws_iam_role" "node" {
  name = "${var.cluster_name}-bootstrap-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
  ])

  role       = aws_iam_role.node.name
  policy_arn = each.value
}

# Pulling from ECR, and nothing else: the three actions of AWS's
# AmazonEC2ContainerRegistryPullOnly, inline rather than attached. That managed
# policy dates from 2024 and floci does not know it; ReadOnly, which it does
# know, also grants listing and describing every repository.
data "aws_iam_policy_document" "node_ecr_pull" {
  statement {
    sid = "EcrPull"
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetAuthorizationToken",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "node_ecr_pull" {
  name   = "ecr-pull"
  role   = aws_iam_role.node.id
  policy = data.aws_iam_policy_document.node_ecr_pull.json
}

resource "aws_iam_role_policy" "node_cilium_operator" {
  name   = "cilium-operator-eni"
  role   = aws_iam_role.node.id
  policy = data.aws_iam_policy_document.cilium_operator.json
}

# Instance metadata answers only on the node itself (one hop): a pod that is
# not hostNetwork cannot borrow the node's role. IMDSv2 only, and an
# encrypted root volume. No variable: none of it is a client's call.
#
# No instance type here: a Spot group takes its list through the node group,
# where AWS spreads it over pools.
resource "aws_launch_template" "bootstrap" {
  name_prefix = "${var.cluster_name}-bootstrap-"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags, { Name = "${var.cluster_name}-bootstrap" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.tags, { Name = "${var.cluster_name}-bootstrap" })
  }

  tags = local.tags
}

# Spot by default, over several instance types: each type in each AZ is its
# own capacity pool, so the two nodes are not reclaimed together, and EKS
# replaces a node at risk before draining it (Capacity Rebalancing). On
# demand, the first type is used. min = max = desired: nothing scales this
# group, so one number. Untainted: until Karpenter exists it is the cluster's
# only compute, and every catalog module has to schedule on it. The private
# subnets, one node per AZ first.
resource "aws_eks_node_group" "bootstrap" {
  cluster_name           = aws_eks_cluster.socle.name
  node_group_name_prefix = "bootstrap-"
  node_role_arn          = aws_iam_role.node.arn
  subnet_ids             = local.private_subnet_ids

  # Follows the control plane: an upgrade rolls these nodes after it.
  version        = aws_eks_cluster.socle.version
  ami_type       = local.bootstrap_node_arm64 ? "AL2023_ARM_64_STANDARD" : "AL2023_x86_64_STANDARD"
  capacity_type  = var.bootstrap_node_capacity_type
  instance_types = var.bootstrap_node_instance_types

  scaling_config {
    min_size     = var.bootstrap_node_count
    max_size     = var.bootstrap_node_count
    desired_size = var.bootstrap_node_count
  }

  # One node at a time, so CoreDNS keeps a replica through a rollout.
  update_config {
    max_unavailable = 1
  }

  launch_template {
    id      = aws_launch_template.bootstrap.id
    version = aws_launch_template.bootstrap.latest_version
  }

  tags = local.tags

  # A new list of types or a new architecture replaces the group: the new
  # one joins before the old one drains, so the cluster is never without a
  # node.
  lifecycle {
    create_before_destroy = true
  }

  # Nodes pull their first images through the NAT Gateway, and join with the
  # role's policies already attached.
  depends_on = [
    aws_iam_role_policy_attachment.node,
    aws_iam_role_policy.node_ecr_pull,
    aws_iam_role_policy.node_cilium_operator,
    aws_route_table_association.private,
  ]
}
