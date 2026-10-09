---
title: AWS decisions
description: The decisions behind the AWS foundations, one per section, each with its status.
sidebar:
  order: 2
---

The AWS foundations ([`opentofu/aws`](../../opentofu/aws)) build an EKS
Standard cluster with Cilium in place of the VPC CNI and kube-proxy
([AWS-01](#aws-01-eks-standard-not-auto-mode)), where pods get AWS credentials
only through Pod Identity ([AWS-03](#aws-03-pod-identity-not-irsa)).

## AWS-01: EKS Standard, not Auto Mode

**accepted** · 2026-09-08 · [`opentofu/aws/cluster.tf`](../../opentofu/aws/cluster.tf)

**Decision.** EKS Standard, with no Auto Mode option: the cluster has no
`compute_config` or `storage_config` block. Karpenter is to run self-hosted,
as a catalog module.

**Context.** Auto Mode locks the CNI to the VPC CNI and the AMI to
Bottlerocket, hides Karpenter's logs and pins its version, and adds a fee of
about 12 % of the on-demand price, the same flat fee on Spot. The socle runs
Cilium on every cloud.

**Consequences.** Cilium, CoreDNS, the CSI drivers, Karpenter and AMI refresh
are the socle's to version and diagnose. Until Karpenter exists
([#53](https://github.com/do-now-io/socle/issues/53)), the bootstrap node group
([AWS-17](#aws-17-a-bootstrap-node-group-of-two-spot-nodes)) is the only
compute. On a reference estate, Auto Mode would add about $288 a month, 58 %
of the Spot bill (eu-west-3, September 2026).

**Sources.** [EKS Auto Mode FAQ](https://docs.aws.amazon.com/eks/latest/best-practices/automode.html#_faq) · [Alternate CNI plugins for EKS](https://docs.aws.amazon.com/eks/latest/userguide/alternate-cni-plugins.html) · [EKS pricing](https://aws.amazon.com/eks/pricing/) · [EC2 Spot pricing](https://aws.amazon.com/ec2/spot/pricing/).

## AWS-02: VPC CNI and kube-proxy refused; AWS-only add-ons stay EKS add-ons

**accepted** · 2026-09-08, revised 2026-09-30 · [`opentofu/aws/cluster.tf`](../../opentofu/aws/cluster.tf), [`opentofu/bootstrap/eks_addons.tf`](../../opentofu/bootstrap/eks_addons.tf), [`opentofu/bootstrap/cilium.tf`](../../opentofu/bootstrap/cilium.tf)

**Decision.** `bootstrap_self_managed_addons = false`: no VPC CNI, kube-proxy
or CoreDNS. The Pod Identity Agent, the EBS and EFS CSI drivers and the
snapshot controller are EKS add-ons at pinned versions, created by the
bootstrap once nodes run; CoreDNS is installed by Helm after Cilium (moved
from an add-on in the 2026-09-30 revision).

**Context.** A component with no equivalent on another cloud stays AWS's; one
that runs everywhere is the socle's. A Deployment add-on cannot become
`ACTIVE` before a CNI exists, and the aws provider waits until it times out.

**Consequences.** Cilium needs the API server's address explicitly; nodes
join `NotReady` until it runs. The socle tracks CoreDNS versions. Each
driver's IAM role sits beside its add-on, outside Crossplane's path
([AWS-18](#aws-18-crossplanes-identity-and-its-permissions-boundary-in-the-foundations));
the order is [SOCLE-02](socle.md#socle-02-cilium-and-coredns-before-flux-from-the-bootstrap).

**Sources.** [CreateCluster, `bootstrapSelfManagedAddons`](https://docs.aws.amazon.com/eks/latest/APIReference/API_CreateCluster.html) · [Cilium kube-proxy-free](https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/) · [Cilium EKS requirements](https://docs.cilium.io/en/stable/installation/requirements-eks/) · [`aws_eks_addon`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_addon).

## AWS-03: Pod Identity, not IRSA

**accepted** · 2026-09-08 · [`opentofu/aws/iam.tf`](../../opentofu/aws/iam.tf)

**Decision.** Pod Identity only: no IAM OIDC provider, no IRSA toggle. Every
role trusts `pods.eks.amazonaws.com` with `sts:AssumeRole` and
`sts:TagSession`.

**Context.** Pod Identity is AWS's recommendation; its restriction to EC2
nodes fits a socle with no Fargate, and Crossplane's AWS providers, the CSI
drivers and Karpenter support it.

**Consequences.** The Pod Identity Agent is installed before the Flux
Operator: without it, associations hang without an error. The OIDC issuer URL
stays an output that nothing in the socle uses.

**Sources.** [EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html) · [Upbound AWS provider, Pod Identity](https://docs.upbound.io/manuals/packages/providers/aws-auth/aws-pod-identity/).

## AWS-04: Upgrade Insights as a pipeline pre-check

**proposed** · 2026-09-08 · [`opentofu/aws/cluster.tf`](../../opentofu/aws/cluster.tf), [`opentofu/aws/variables.tf`](../../opentofu/aws/variables.tf)

**Decision.** The version pipeline calls `list-insights` before every upgrade
and stops on an `ERROR` finding; required, never the only check.
`force_update_version` (default `false`) is the override.

**Context.** Upgrade Insights is the only check that sees the client's own
workloads, but it reads 30 days of audit logs
([containers-roadmap#2569](https://github.com/aws/containers-roadmap/issues/2569)),
and AWS rolled back blocking `UpdateClusterVersion` on a finding.

**Consequences.** Only `force_update_version` is built; until the pipeline
exists, nothing stops an upgrade on a finding.

**Sources.** [`list-insights`](https://docs.aws.amazon.com/cli/latest/reference/eks/list-insights.html) · [containers-roadmap#2570](https://github.com/aws/containers-roadmap/issues/2570).

## AWS-05: Backup with Velero, not AWS Backup

**accepted** · 2026-09-08 · [`oci/catalog/velero`](../../oci/catalog/velero), [velero module](../catalog/velero.md)

**Decision.** Velero, as a catalog module; AWS Backup is not the default.

**Context.** Both snapshot the same EBS volumes; Velero does it on every
cloud.

**Consequences.** One restore procedure and one rehearsal on four clouds. The
bucket and role come from the velero module through Crossplane; EBS volumes
need the snapshot controller
([AWS-02](#aws-02-vpc-cni-and-kube-proxy-refused-aws-only-add-ons-stay-eks-add-ons)).

**Sources.** [What is AWS Backup](https://docs.aws.amazon.com/aws-backup/latest/devguide/whatisbackup.html) · [Velero](https://velero.io/docs/latest/).

## AWS-06: IPv6 refused

**accepted** · 2026-09-09 · [`opentofu/aws/variables.tf`](../../opentofu/aws/variables.tf)

**Decision.** No IPv6 cluster, and no variable for one.

**Context.** EKS IPv6 is irreversible and documented with the VPC CNI.
Cilium's ENI IPv6 IPAM is beta
([cilium#18405](https://github.com/cilium/cilium/issues/18405)) and cannot
intercept IPv4 over `v4if0` ([cilium#28409](https://github.com/cilium/cilium/issues/28409)).

**Consequences.** Clusters are IPv4. Revisit when both Cilium issues close.

**Sources.** [EKS IPv6 clusters](https://docs.aws.amazon.com/eks/latest/userguide/cni-ipv6.html).

## AWS-07: Security groups for pods refused

**accepted** · 2026-09-09 · [`opentofu/aws/cluster.tf`](../../opentofu/aws/cluster.tf)

**Decision.** Not offered.

**Context.** It is a VPC CNI feature, and the socle does not run the VPC CNI
([AWS-02](#aws-02-vpc-cni-and-kube-proxy-refused-aws-only-add-ons-stay-eks-add-ons)).

**Consequences.** Pod-level network control is Cilium's network policy, the
same on every cloud.

**Sources.** [Security groups for pods](https://docs.aws.amazon.com/eks/latest/userguide/security-groups-for-pods.html).

## AWS-08: Gateway API through the AWS Load Balancer Controller

**superseded by [GATEWAY-API-02](gateway-api.md#gateway-api-02-shared-public-and-private-gateways-on-cilium)** · 2026-09-09, superseded 2026-09-30 · [`opentofu/aws/certificate.tf`](../../opentofu/aws/certificate.tf)

**Decision.** The AWS Load Balancer Controller was to implement Gateway API
on AWS: ALB by default, NLB as an option.

**Context.** It implements Gateway API since v3.0.0.

**Consequences.** Replaced when Cilium became the implementation on every
cloud, behind NLBs EKS's in-tree controller creates. The foundations provide
only the ACM certificate (`gateway_certificate`); no Load Balancer Controller
is installed.

**Sources.** [aws-load-balancer-controller v3.0.0](https://github.com/kubernetes-sigs/aws-load-balancer-controller/releases/tag/v3.0.0) · [aws-load-balancer-controller#4400](https://github.com/kubernetes-sigs/aws-load-balancer-controller/issues/4400).

## AWS-09: GuardDuty EKS Protection as a catalog option

**superseded by [AWS-14](#aws-14-guardduty-is-the-account-owners)** · 2026-09-09, superseded 2026-09-10

**Decision.** It was to be a catalog option, off by default.

**Context.** GuardDuty EKS Protection has Audit Log and Runtime Monitoring,
priced separately.

**Consequences.** Dropped: GuardDuty has one detector per account and region,
so a per-cluster toggle cannot work.

**Sources.** [GuardDuty pricing](https://aws.amazon.com/guardduty/pricing/).

## AWS-10: Secrets encrypted with KMS by default

**accepted** · 2026-09-09 · [`opentofu/aws/cluster.tf`](../../opentofu/aws/cluster.tf), [`opentofu/aws/variables.tf`](../../opentofu/aws/variables.tf)

**Decision.** On by default (`secrets_encryption_enabled = true`), with a
rotated key of the module's own unless `secrets_encryption_kms_key_arn` names
one.

**Context.** EKS envelope-encrypts Secrets with a KMS key for about $1 a month.

**Consequences.** One key per cluster; turning it off is the client's
explicit choice.

**Sources.** [Enable KMS secrets encryption](https://docs.aws.amazon.com/eks/latest/userguide/enable-kms.html).

## AWS-11: Public API endpoint, restricted by CIDR, private access on

**accepted** · 2026-09-09 · [`opentofu/aws/cluster.tf`](../../opentofu/aws/cluster.tf), [`opentofu/aws/variables.tf`](../../opentofu/aws/variables.tf)

**Decision.** Public and private endpoint access both on, with no variable.
`cluster_endpoint_public_access_cidrs` is required, and `0.0.0.0/0` is
refused at plan.

**Context.** The apply and pipelines reach the API from outside the VPC; a
private-only endpoint needs a bastion or VPN the module does not own.

**Consequences.** The applying runner must be inside one of the CIDRs, since
the helm provider talks to the API in the same apply. Nodes reach it
privately.

**Sources.** [Cluster endpoint access control](https://docs.aws.amazon.com/eks/latest/userguide/config-cluster-endpoint.html).

## AWS-12: Reference network, public and private per AZ

**accepted** · 2026-09-09 · [`opentofu/aws/network.tf`](../../opentofu/aws/network.tf)

**Decision.** A created VPC has one public and one private subnet per AZ, at
least two AZs, one NAT Gateway per AZ, an S3 gateway endpoint, and interface
endpoints for `ecr.api`, `ecr.dkr`, `sts`, `ec2` and `logs`. Nodes run
private.

**Context.** ISO 27001 (A.8.22) and SOC 2 (CC6) expect network segmentation.
An interface endpoint costs about $7.30 a month per AZ; one NAT adds cross-AZ
charges.

**Consequences.** STS and EC2 calls, which Pod Identity and Cilium's IPAM
depend on, avoid NAT. A client VPC (`create_vpc = false`) gets no endpoint
and no flow log.

**Sources.** [VPC pricing](https://aws.amazon.com/vpc/pricing/) · [PrivateLink pricing](https://aws.amazon.com/privatelink/pricing/) · [ISO 27001:2022 A.8.22](https://www.isms.online/iso-27001/annex-a-2022/8-22-segregation-of-networks-2022/) · [SOC 2 CC6](https://secureframe.com/hub/soc-2/common-criteria).

## AWS-13: Cloud resources observed from a central cluster

**proposed** · 2026-09-09

**Decision.** YACE in a central observability cluster reads AWS service
metrics every 300 seconds; cost through CUR / Data Exports to the client's
bucket on the socle's cost-allocation tag; unmanaged resources through the
Tagging API.

**Context.** `GetMetricData` bills reads at $0.01 per 1,000 metrics: about
$8.64 a month for 100 series at 300 seconds, $43.20 at 60. Metric Streams is
cheaper only below about 190 seconds.

**Consequences.** Nothing is built. The in-cluster stack is
[SOCLE-03](socle.md#socle-03-one-in-cluster-monitoring-stack-on-every-cloud).

**Sources.** [`GetMetricData`](https://docs.aws.amazon.com/AmazonCloudWatch/latest/APIReference/API_GetMetricData.html) · [YACE](https://github.com/prometheus-community/yet-another-cloudwatch-exporter) · [AWS Data Exports](https://aws.amazon.com/about-aws/whats-new/2023/11/aws-billing-cost-management-data-exports) · [Resource Groups Tagging API](https://docs.aws.amazon.com/resourcegroupstagging/latest/APIReference/Welcome.html).

## AWS-14: GuardDuty is the account owner's

**accepted** · 2026-09-10 · [`opentofu/aws/variables.tf`](../../opentofu/aws/variables.tf)

**Decision.** No GuardDuty variable, no detector. GuardDuty is configured by
whoever owns the account.

**Context.** One detector per account and region; two clusters' applies would
fight over it.

**Consequences.** A cluster is protected only if the account owner turned
GuardDuty on in its region; the socle neither checks nor reports it.

**Sources.** [GuardDuty pricing](https://aws.amazon.com/guardduty/pricing/).

## AWS-15: No extended support

**accepted** · 2026-09-10 · [`opentofu/aws/cluster.tf`](../../opentofu/aws/cluster.tf)

**Decision.** `upgrade_policy.support_type = "STANDARD"`, hardcoded.

**Context.** After 14 months of standard support, extended support costs six
times the control plane rate; AWS's default is `EXTENDED`, and a cluster
cannot leave it until upgraded.

**Consequences.** AWS upgrades the cluster itself at the end of standard
support. [SOCLE-05](socle.md#socle-05-the-kubernetes-version-moves-by-rings-n-1-then-n)
should upgrade first; this is the floor.

**Sources.** [EKS Kubernetes versions](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html).

## AWS-16: The account keeps custody of the logs

**accepted**, its control-plane log types **superseded by [AWS-19](#aws-19-control-plane-logs-off-by-default-opt-in-per-type)** · 2026-09-10, superseded 2026-10-07 · [`opentofu/aws/cluster.tf`](../../opentofu/aws/cluster.tf), [`opentofu/aws/network.tf`](../../opentofu/aws/network.tf)

**Decision.** The module creates the control-plane and flow-log groups
itself, with `log_retention_days` (default 90) and one rotated
customer-managed KMS key. All five control-plane log types are on; VPC flow
logs record all traffic (`vpc_flow_logs_enabled`, default `true`).

**Context.** Audit and flow logs are what ISO 27001 A.8.15 and SOC 2 CC7
expect; implicitly created log groups never expire.

**Consequences.** One more KMS key per cluster. Trimming `cluster_log_types`
cuts ingestion cost; an empty list turns it off.

**Sources.** [EKS control plane logs](https://docs.aws.amazon.com/eks/latest/userguide/control-plane-logs.html) · [Encrypt log data with KMS](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/encrypt-log-data-kms.html).

## AWS-17: A bootstrap node group of two Spot nodes

**accepted** · 2026-09-24 · [`opentofu/aws/nodes.tf`](../../opentofu/aws/nodes.tf), [`opentofu/aws/variables.tf`](../../opentofu/aws/variables.tf)

**Decision.** One managed node group of two untainted nodes, `SPOT` over six
4-vCPU Graviton families (`t4g`, `m7g`, `m6g`, `c7g`, `c6g`, `r6g`), AL2023,
IMDSv2, private subnets. `bootstrap_node_capacity_type = "ON_DEMAND"` takes
the first type.

**Context.** Karpenter, Cilium's operator, CoreDNS and Flux need a node
first. One instance type on Spot is one pool per AZ, which a reclaim can
empty at once.

**Consequences.** Each type alone carries the socle, so a reclaim is routine.
Until Karpenter, every workload runs here. About $84 a month on Spot,
eu-west-3, September 2026 ([cost](../clouds/aws/index.md#cost)).

**Sources.** [Managed node groups, Spot](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html#managed-node-group-capacity-types) · [Spot Instance Advisor](https://aws.amazon.com/ec2/spot/instance-advisor/).

## AWS-18: Crossplane's identity and its permissions boundary in the foundations

**accepted** · 2026-09-24 · [`opentofu/aws/iam.tf`](../../opentofu/aws/iam.tf)

**Decision.** With `crossplane` set, the foundations create `<cluster>-crossplane`,
its Pod Identity association, and a boundary. The role writes roles only
under `/socle/<cluster>/` with that boundary, and creates but never deletes
buckets `<cluster>-*`. The boundary allows `crossplane.allowed_services` and
always denies `iam`, `sts`, `organizations`, `account`, `sso`, `identitystore`.

**Context.** Modules declare their own cloud access
([SOCLE-04](socle.md#socle-04-each-module-owns-its-cloud-access-the-foundations-never-change)),
so something must create Crossplane's role, the most powerful in the cluster.

**Consequences.** A new AWS service is one word in `allowed_services`. A
trust policy cannot be bounded: a compromised Crossplane could make an
assumable role within the boundary. The applier needs `iam:CreatePolicy`.

**Sources.** [Permissions boundaries](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_boundaries.html) · [crossplane module](../catalog/crossplane.md).

## AWS-19: Control-plane logs off by default, opt-in per type

**accepted** · 2026-10-07 · [`opentofu/aws/variables.tf`](../../opentofu/aws/variables.tf) (`cluster_log_types`), [`opentofu/aws/cluster.tf`](../../opentofu/aws/cluster.tf)

**Decision.** `cluster_log_types` defaults to `[]`. The log group, its
retention and its KMS key are still created
([AWS-16](#aws-16-the-account-keeps-custody-of-the-logs)), so a client whose
audit expects the API server's record turns on `audit` and `authenticator`
with one line.

**Context.** CloudWatch bills ingestion by the gigabyte, and the audit stream
records every request to the API server: one controller writing in a loop
(Crossplane's providers taking a ServiceAccount from one another, #80) made it
about $40 a day on an idle cluster.

**Consequences.** By default no record of who did what to the API server is
kept; ISO 27001 A.8.15 and SOC 2 CC7 clients opt in. Trivy's AVD-AWS-0038 is
ignored on the cluster, with this as its reason.

**Sources.** [EKS control plane logs](https://docs.aws.amazon.com/eks/latest/userguide/control-plane-logs.html) · #80.
