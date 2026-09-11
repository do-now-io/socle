# --- Deployment identity ---

variable "cluster_name" {
  description = "Name shared by the VPC, the EKS cluster and every resource this module creates around them."
  type        = string

  validation {
    condition     = can(regex("^[0-9A-Za-z][A-Za-z0-9-_]{0,99}$", var.cluster_name))
    error_message = "cluster_name must be 1-100 characters, starting with a letter or digit, and contain only letters, digits, hyphens and underscores — the EKS cluster name constraint."
  }
}

variable "owner" {
  description = "Stamped on every billable resource so cost can be attributed and orphans can be found."
  type        = string
}

variable "environment" {
  description = "Stamped on every billable resource. Also what the factory's upgrade rings (dev/staging/prod) key off."
  type        = string
}

variable "additional_tags" {
  description = "Extra tags merged onto every resource this module creates, on top of owner/environment/socle-version."
  type        = map(string)
  default     = {}
}

# --- Network — docs/aws/eks-network-security.md ---

# IPv6 is absent by decision, not by omission: Socle's Cilium-as-VPC-CNI
# stack is untested and unsupported for it today (Cilium's ENI IPv6 IPAM
# mode is still beta, cilium#18405/#28409). Revisit when that closes.

variable "create_vpc" {
  description = "Create the VPC, or attach to one the consumer already manages."
  type        = bool
  default     = true
}

variable "vpc_id" {
  description = "Existing VPC to attach to. Required when create_vpc is false, and incoherent to set when create_vpc is true — this module cannot both create a VPC and attach to a different one."
  type        = string
  default     = null

  validation {
    condition     = var.create_vpc == (var.vpc_id == null)
    error_message = "vpc_id must be set when create_vpc is false, and left null when create_vpc is true."
  }
}

variable "private_subnet_ids" {
  description = "Existing private subnet IDs, one per AZ in availability_zones. Required when create_vpc is false — this module carves its own subnets out of vpc_cidr only when it also creates the VPC."
  type        = list(string)
  default     = []

  validation {
    condition     = var.create_vpc || length(var.private_subnet_ids) == length(var.availability_zones)
    error_message = "private_subnet_ids must list exactly one subnet per AZ in availability_zones when create_vpc is false."
  }
}

variable "public_subnet_ids" {
  description = "Existing public subnet IDs, one per AZ in availability_zones. Required when create_vpc is false — same reasoning as private_subnet_ids."
  type        = list(string)
  default     = []

  validation {
    condition     = var.create_vpc || length(var.public_subnet_ids) == length(var.availability_zones)
    error_message = "public_subnet_ids must list exactly one subnet per AZ in availability_zones when create_vpc is false."
  }
}

variable "vpc_cidr" {
  description = "CIDR for the VPC when this module creates it. Arbitrary default (not a research decision) — a /16 large enough for any socle estate."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = <<-EOT
    AZs the VPC's public and private subnets are spread across. Every VPC
    gets at least one public and one private subnet per AZ — never a flat,
    all-public layout — to satisfy ISO 27001 A.8.22 and SOC 2 CC6 network
    segregation. There is no all-public escape hatch: the private tier is
    structural, whether or not a client's workloads use it.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "availability_zones must list at least two AZs — EKS itself requires two for the control plane."
  }
}

variable "create_nat_gateway" {
  description = <<-EOT
    Create one NAT Gateway per AZ. One per AZ, never a single shared one, to
    avoid cross-AZ data transfer charges — not a toggle for disabling NAT
    outright, which the private-subnet decision above rules out. Exists
    only for the create_vpc = false case, where the consumer's existing VPC
    already manages its own NAT.
  EOT
  type        = bool
  default     = true

  validation {
    condition     = var.create_nat_gateway || !var.create_vpc
    error_message = "create_nat_gateway can only be false when create_vpc is also false. A VPC this module creates has private subnets whose only egress path is its own NAT Gateway; without it they reach nothing."
  }
}

variable "vpc_flow_logs_enabled" {
  description = "Record accepted and rejected traffic on the VPC this module creates. On by default, aggregated over ten-minute windows to keep the volume down: it is the only record of who talked to whom, and the segmentation this VPC is built around is unauditable without it."
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  description = <<-EOT
    CIDRs allowed to reach the public EKS API endpoint. Required, no
    default: the endpoint is restricted by CIDR rather than left open or
    made fully private-only (AWS's own recommended pattern for this case),
    and there is no globally correct default to authorize on a client's
    behalf.
  EOT
  type        = list(string)

  validation {
    condition     = !contains(var.cluster_endpoint_public_access_cidrs, "0.0.0.0/0")
    error_message = "cluster_endpoint_public_access_cidrs must not include 0.0.0.0/0 — that defeats the CIDR restriction this variable exists for."
  }
}

# GuardDuty EKS Protection (catalog option per the research doc — Audit
# Log Monitoring and Runtime Monitoring, either enabled alone) has no
# variable here: GuardDuty is a single detector per account per region,
# not per cluster. A client with several clusters in one AWS account would
# have two separate applies of this module fight over the same detector
# and its features. Out of this module's scope — an account-level
# prerequisite, documented alongside the state bucket and IAM roles, not
# something this module toggles.

variable "secrets_encryption_enabled" {
  description = "Envelope-encrypt Kubernetes Secrets via KMS. On by default: essentially free (~$1/month per key, negligible per-request cost), and standard on Kubernetes 1.28+ already."
  type        = bool
  default     = true
}

variable "secrets_encryption_kms_key_arn" {
  description = "Existing KMS key for Secrets envelope encryption. Leave unset and the module creates its own key. Ignored when secrets_encryption_enabled is false."
  type        = string
  default     = null
}

# Gateway endpoints (S3, DynamoDB) and Interface endpoints (ECR, STS, EC2,
# CloudWatch Logs) have no toggle: the doc calls the former "always on"
# (strictly free) and the latter "standard" (isolation for load-bearing
# STS/EC2 traffic — Pod Identity, Karpenter — not a cost optimisation).
# Both are created unconditionally in network.tf.

# Security groups for pods is not applicable, by construction: it is a VPC
# CNI (ENI trunking) feature, and Socle does not run VPC CNI. Cilium already
# covers the same ground in eBPF. Nothing to configure, nothing to refuse.

# Exposure (Gateway API, ALB vs NLB) has no variable here: the AWS Load
# Balancer Controller is a factory component delivered through the socle
# OCI artifact, like Karpenter and Cilium — not provisioned by this module.

variable "cluster_log_types" {
  description = <<-EOT
    Control plane log types shipped to CloudWatch Logs. All five by default:
    the audit and authenticator streams are the only record of who did what
    to the API server, which ISO 27001 A.8.15 and SOC 2 CC7 both expect, and
    the same argument that puts a private subnet tier in every VPC applies
    here. Trim the list to cut ingestion cost; an empty list turns control
    plane logging off entirely.
  EOT
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  validation {
    condition = alltrue([
      for t in var.cluster_log_types :
      contains(["api", "audit", "authenticator", "controllerManager", "scheduler"], t)
    ])
    error_message = "cluster_log_types accepts only api, audit, authenticator, controllerManager and scheduler — the five EKS publishes."
  }
}

variable "log_retention_days" {
  description = "Retention for the log groups this module creates — the control plane's and the VPC flow logs'. Set explicitly because a log group left to AWS never expires."
  type        = number
  default     = 90

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be one of the retention periods CloudWatch Logs accepts (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653)."
  }
}

# --- Add-ons and identity — docs/aws/eks-managed-scope.md ---

# No add-on variable here at all. VPC CNI and kube-proxy are refused outright
# — Cilium replaces both, and the cluster is created without them. CoreDNS,
# EBS CSI, EFS CSI and the Pod Identity Agent remain EKS-managed add-ons, but
# they are installed by the factory once compute exists, at versions the socle
# pipeline pins. This module creates no node, so an add-on installed here
# would have nowhere to run — see cluster.tf.

variable "kubernetes_version" {
  description = <<-EOT
    EKS control plane version. Required, no default: the module accepts
    whatever version it is given rather than enforcing the policy ceiling
    itself. The n-1 policy ceiling / n-2 compatibility floor is decided and
    bumped by the socle Kargo pipelines, not by this module — a `validation`
    block cannot call the AWS API to know what "current" is, and the
    decoupled socle-release/Kubernetes-version pipelines are the actual
    owners of that decision.
  EOT
  type        = string

  validation {
    condition     = can(regex("^1\\.\\d+$", var.kubernetes_version))
    error_message = "kubernetes_version must look like \"1.34\" (major.minor, no patch — EKS versions Kubernetes at that granularity)."
  }
}

variable "force_update_version" {
  description = <<-EOT
    Force the control plane version update even if Upgrade Insights reports
    blocking findings. Default false: Upgrade Insights is a mandatory
    pre-check, never sufficient alone (it only sees the client's own
    removed-API usage, over a rolling 30-day audit-log window that both
    misses infrequent calls and over-reports fixed ones) — but AWS's own
    blocking of `update-cluster-version` on ERROR findings is currently
    rolled back, so this module does not assume AWS enforces the check
    either.
  EOT
  type        = bool
  default     = false
}

variable "cluster_support_type" {
  description = <<-EOT
    What happens when this cluster's Kubernetes version reaches the end of
    standard support, 14 months after its EKS release.

    EXTENDED, the default here and AWS's own: nothing is upgraded. The cluster
    enters extended support and the control plane goes from $0.10 to $0.60 an
    hour — around +$365 a month — until it is moved back onto a supported
    version. The socle pipelines keep deciding when that happens, which is the
    whole point of owning the version ceiling.

    STANDARD: AWS upgrades the cluster itself at the end of standard support,
    on its own schedule, and no extended-support charge is ever possible. It
    trades a silent bill for a control plane upgrade nobody here scheduled.

    Not reversible under pressure: a cluster already in extended support cannot
    be moved to STANDARD until it is upgraded onto a version still in standard
    support.
  EOT
  type        = string
  default     = "EXTENDED"

  validation {
    condition     = contains(["EXTENDED", "STANDARD"], var.cluster_support_type)
    error_message = "cluster_support_type must be EXTENDED or STANDARD — the two values the EKS upgrade policy accepts."
  }
}

# Pod Identity is the only workload-identity mechanism this module wires up
# — IRSA is absent, not toggled off: AWS's own recommendation, and its
# EC2-only restriction matches Socle's EC2-only scope exactly. The OIDC
# issuer URL is still exposed as an output (checklist requirement) even
# though nothing here consumes it — it provisions no IRSA trust relationship.

variable "crossplane_service_account_namespace" {
  description = "Namespace of the in-cluster Crossplane AWS provider's Kubernetes service account."
  type        = string
  default     = "crossplane-system"
}

variable "crossplane_service_account_name" {
  description = "Name of the in-cluster Crossplane AWS provider's Kubernetes service account. Must match the socle's DeploymentRuntimeConfig — the provider Pod's service account name is not stable across provider revisions unless it is pinned there."
  type        = string
  default     = "provider-aws"
}

variable "crossplane_policy_arns" {
  description = "IAM policy ARNs granted to the identity the in-cluster Crossplane AWS provider assumes. Empty by default: the catalog does not exist yet, and a list written today would be a guess."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for a in var.crossplane_policy_arns :
      can(regex("^arn:aws:iam::(aws|[0-9]{12}):policy/", a))
    ])
    error_message = "Each entry must be an IAM policy ARN, such as arn:aws:iam::aws:policy/ReadOnlyAccess or a customer-managed policy ARN."
  }
}
