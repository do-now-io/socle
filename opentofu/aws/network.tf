# Network — docs/aws/eks-network-security.md.
#
# One VPC, at least one public and one private subnet per AZ — never a
# flat, all-public layout, even for a client whose workloads all end up in
# the public tier. ISO 27001 A.8.22 and SOC 2 CC6 both expect demonstrated
# network segmentation as a control, and neither names an exact subnet
# count — but a fully public VPC is a common finding against both during an
# audit. There is no all-public escape hatch: the private tier is
# structural here, whether or not a client's workloads use it.

resource "aws_vpc" "socle" {
  count = var.create_vpc ? 1 : 0

  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, { Name = var.cluster_name })
}

# Tagged for the AWS Load Balancer Controller and Karpenter's own subnet
# auto-discovery — a network-level artifact this module has to lay down
# now, even though the controllers themselves are factory components
# installed later through the socle OCI artifact, not by this module.
# "owned" rather than "shared": this VPC belongs to one cluster only.

resource "aws_subnet" "private" {
  count = var.create_vpc ? local.az_count : 0

  vpc_id            = local.vpc_id
  availability_zone = var.availability_zones[count.index]
  cidr_block        = local.private_subnet_cidrs[count.index]

  tags = merge(local.tags, {
    Name                                        = "${var.cluster_name}-private-${var.availability_zones[count.index]}"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  })
}

resource "aws_subnet" "public" {
  count = var.create_vpc ? local.az_count : 0

  vpc_id            = local.vpc_id
  availability_zone = var.availability_zones[count.index]
  cidr_block        = local.public_subnet_cidrs[count.index]

  # No auto-assigned public IP: nothing this module places here needs one.
  # NAT Gateways carry their own EIP and load balancers their own addresses.
  # A workload that genuinely needs a public IP asks for one explicitly.

  tags = merge(local.tags, {
    Name                                        = "${var.cluster_name}-public-${var.availability_zones[count.index]}"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  })
}

resource "aws_internet_gateway" "socle" {
  count = var.create_vpc ? 1 : 0

  vpc_id = local.vpc_id
  tags   = merge(local.tags, { Name = var.cluster_name })
}

# One route table for every public subnet — the Internet Gateway is a
# single regional resource, not AZ-bound, so there is nothing to split per
# AZ here. The private side is the opposite: see below.

resource "aws_route_table" "public" {
  count = var.create_vpc ? 1 : 0

  vpc_id = local.vpc_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.socle[0].id
  }

  tags = merge(local.tags, { Name = "${var.cluster_name}-public" })
}

resource "aws_route_table_association" "public" {
  count = var.create_vpc ? local.az_count : 0

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

# One EIP and one NAT Gateway per AZ, each living in that AZ's own public
# subnet — never a single shared NAT, to avoid cross-AZ data transfer
# charges. Optional: create_nat_gateway is false only when create_vpc is
# also false and the consumer's existing VPC already manages its own NAT
# or an alternate egress path (e.g. a Transit Gateway to a hub VPC).

resource "aws_eip" "nat" {
  count = var.create_vpc && var.create_nat_gateway ? local.az_count : 0

  domain = "vpc"
  tags   = merge(local.tags, { Name = "${var.cluster_name}-nat-${var.availability_zones[count.index]}" })
}

resource "aws_nat_gateway" "socle" {
  count = var.create_vpc && var.create_nat_gateway ? local.az_count : 0

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = merge(local.tags, { Name = "${var.cluster_name}-${var.availability_zones[count.index]}" })

  # A NAT Gateway is useless without a route to the internet already in
  # place on the subnet it sits in.
  depends_on = [aws_internet_gateway.socle]
}

# One route table per AZ, matching that AZ's own NAT Gateway — the private
# tier's counterpart to the single shared public route table above.

resource "aws_route_table" "private" {
  count = var.create_vpc ? local.az_count : 0

  vpc_id = local.vpc_id

  dynamic "route" {
    for_each = var.create_nat_gateway ? [1] : []

    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.socle[count.index].id
    }
  }

  tags = merge(local.tags, { Name = "${var.cluster_name}-private-${var.availability_zones[count.index]}" })
}

resource "aws_route_table_association" "private" {
  count = var.create_vpc ? local.az_count : 0

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Gateway endpoint (S3) always on: strictly free, no reason not to have
# it. Interface endpoints (ECR, STS, EC2, CloudWatch Logs) standard:
# isolation for STS/EC2 traffic load-bearing for the cluster (Pod
# Identity, Karpenter), not a cost optimisation — neither is a toggle.
# Both gated on create_vpc: this module only manages endpoints on the VPC
# and route tables it also manages.
#
# DynamoDB dropped: no cited Socle use case, here or in
# docs/aws/cloud-observability.md — see docs/aws/eks-network-security.md.

resource "aws_vpc_endpoint" "s3" {
  count = var.create_vpc ? 1 : 0

  vpc_id            = local.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat(aws_route_table.public[*].id, aws_route_table.private[*].id)

  tags = merge(local.tags, { Name = "${var.cluster_name}-s3" })
}

# Interface endpoints need their own security group: HTTPS from inside the
# VPC, nothing else — these ENIs answer AWS API calls, not workload
# traffic.

resource "aws_security_group" "vpc_endpoints" {
  count = var.create_vpc ? 1 : 0

  # name_prefix, not name: any change to this group forces a replacement, and
  # a fixed name makes the replacement collide with the group still in place.
  name_prefix = "${var.cluster_name}-vpc-endpoints-"
  description = "Allow HTTPS from inside the VPC to interface endpoints."
  vpc_id      = local.vpc_id

  lifecycle {
    create_before_destroy = true
  }

  ingress {
    description = "HTTPS from the VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(local.tags, { Name = "${var.cluster_name}-vpc-endpoints" })
}

locals {
  # ECR needs both: api for control-plane calls (auth, image manifests),
  # dkr for the actual image layer pulls. Keyed by service name, not by
  # position — order doesn't matter here, unlike the AZ-indexed subnets
  # above, so for_each fits better than count.
  interface_endpoint_services = ["ecr.api", "ecr.dkr", "sts", "ec2", "logs"]
}

resource "aws_vpc_endpoint" "interface" {
  for_each = var.create_vpc ? toset(local.interface_endpoint_services) : []

  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(local.tags, { Name = "${var.cluster_name}-${each.value}" })
}

# Flow logs on the VPC this module creates. The private/public split above is
# a control that has to be demonstrable, and nothing else here records which
# address talked to which. Ten-minute aggregation rather than one, because the
# question these answer is "who reached what", not "in which second".

resource "aws_cloudwatch_log_group" "flow_logs" {
  count = var.create_vpc && var.vpc_flow_logs_enabled ? 1 : 0

  name              = "/aws/vpc/${var.cluster_name}/flow-logs"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.logs.arn

  tags = local.tags
}

resource "aws_iam_role" "flow_logs" {
  count = var.create_vpc && var.vpc_flow_logs_enabled ? 1 : 0

  name = "${var.cluster_name}-vpc-flow-logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.tags
}

# Scoped to this VPC's own log group — there is no AWS-managed policy for
# flow logs, and the documented example grants these five actions on "*".
resource "aws_iam_role_policy" "flow_logs" {
  count = var.create_vpc && var.vpc_flow_logs_enabled ? 1 : 0

  name = "${var.cluster_name}-vpc-flow-logs"
  role = aws_iam_role.flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
      ]
      Resource = [
        aws_cloudwatch_log_group.flow_logs[0].arn,
        "${aws_cloudwatch_log_group.flow_logs[0].arn}:*",
      ]
    }]
  })
}

resource "aws_flow_log" "socle" {
  count = var.create_vpc && var.vpc_flow_logs_enabled ? 1 : 0

  vpc_id                   = local.vpc_id
  traffic_type             = "ALL"
  iam_role_arn             = aws_iam_role.flow_logs[0].arn
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.flow_logs[0].arn
  max_aggregation_interval = 600

  tags = merge(local.tags, { Name = "${var.cluster_name}-flow-logs" })
}
