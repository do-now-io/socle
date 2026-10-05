---
title: AWS decisions
description: The decisions behind the AWS foundations, one per section, each with its status.
sidebar:
  order: 2
---

The AWS foundations ([`opentofu/aws`](../../opentofu/aws)) build an EKS
Standard cluster with Cilium in place of the VPC CNI and kube-proxy, two
bootstrap nodes, and one workload identity, Crossplane's. Two decisions shape
the rest: [AWS-01](#aws-01-eks-standard-not-auto-mode), because Auto Mode
cannot run Cilium, and [AWS-03](#aws-03-pod-identity-not-irsa), the only way
a pod gets AWS credentials. The Kubernetes version policy is the socle's, not
AWS's: [SOCLE-05](socle.md#socle-05-the-kubernetes-version-moves-by-rings-n-1-then-n).
Who owns a module's cloud access is
[SOCLE-04](socle.md#socle-04-each-module-owns-its-cloud-access-the-foundations-never-change);
[AWS-18](#aws-18-crossplanes-identity-and-its-permissions-boundary-in-the-foundations)
is how it is done on AWS.

## AWS-01: EKS Standard, not Auto Mode

**accepted** · 2026-09-08 · [`opentofu/aws/cluster.tf`](../../opentofu/aws/cluster.tf)

**Context.** EKS Auto Mode bundles Karpenter, the VPC CNI, kube-proxy,
CoreDNS, the EBS CSI driver, the AWS Load Balancer Controller and the Pod
Identity Agent, run by AWS. It locks the CNI to the VPC CNI and the AMI to
Bottlerocket, exposes no Karpenter logs, pins the Karpenter version, offers
two built-in NodePools that are on or off, replaces nodes every 21 days, and
adds a fee of about 12 % of the on-demand price, the same flat fee on Spot.
The socle runs Cilium on every cloud. Once Cilium is there, what Auto Mode
would add is a managed Karpenter and an AMI patch pipeline.

**Decision.** EKS Standard, with no Auto Mode option. The `aws_eks_cluster`
has no `compute_config` or `storage_config` block, so Standard is the
absence of a choice, not a variable. Karpenter is to run self-hosted, as a
catalog module.

**Consequences.** Cilium, CoreDNS, the CSI drivers and Karpenter are the
socle's to version and to diagnose, with full log access. AMI refresh and
GPU device plugins are the socle's too. Karpenter is not built yet
([#53](https://github.com/do-now-io/socle/issues/53)): until it is, the
bootstrap node group ([AWS-17](#aws-17-a-bootstrap-node-group-of-two-spot-nodes))
is the cluster's only compute. On a reference estate of 20 vCPU and 128 GiB
(one `i8ge.3xlarge` and one `t4g.2xlarge` per environment; prod 24/7, two UAT
environments 12 hours per working day), priced eu-west-3 in September 2026,
Auto Mode adds about $288 a month on demand ($2,684 against $2,396) and
$288 on Spot ($784 against $496), which is 58 % of the Spot bill. The $73
control plane fee is paid in both modes.

**Sources.** [EKS Auto Mode FAQ](https://docs.aws.amazon.com/eks/latest/best-practices/automode.html#_faq) ·
[Alternate CNI plugins for EKS](https://docs.aws.amazon.com/eks/latest/userguide/alternate-cni-plugins.html) ·
[EKS pricing](https://aws.amazon.com/eks/pricing/) ·
[EC2 on-demand pricing](https://aws.amazon.com/ec2/pricing/on-demand/) ·
[EC2 Spot pricing](https://aws.amazon.com/ec2/spot/pricing/).

## AWS-02: VPC CNI and kube-proxy refused; AWS-only add-ons stay EKS add-ons

**accepted** · 2026-09-08, revised 2026-09-30 · [`opentofu/aws/cluster.tf`](../../opentofu/aws/cluster.tf), [`opentofu/bootstrap/eks_addons.tf`](../../opentofu/bootstrap/eks_addons.tf), [`opentofu/bootstrap/cilium.tf`](../../opentofu/bootstrap/cilium.tf)

**Context.** Each data-plane component is either delegated to EKS as a
managed add-on or run by the socle. The rule: a component with no
equivalent on another cloud stays AWS's; one that runs on every cloud is the
socle's. AWS never upgrades an add-on by itself, so the trigger is always the
socle's. A managed add-on whose pods are a Deployment cannot become `ACTIVE`
before a CNI exists: on a cluster with no CNI it sits `DEGRADED` and the aws
provider waits until it times out.

**Decision.** The cluster is created with `bootstrap_self_managed_addons =
false`: no VPC CNI, kube-proxy or CoreDNS is ever installed. Cilium replaces
the first two with `kubeProxyReplacement`. The Pod Identity Agent, the EBS
CSI driver, the EFS CSI driver (off by default) and the CSI snapshot
controller are EKS add-ons, created by the bootstrap module once the nodes
run, at versions pinned in `eks_addons.tf`, never `most_recent`. CoreDNS is
installed by Helm right after Cilium. The 2026-09-30 revision moved CoreDNS
from a managed add-on to Helm, and added the snapshot controller.

**Consequences.** With no kube-proxy, Cilium needs the API server's address
explicitly; the root passes it from the foundations' outputs. Nodes join
`NotReady` until Cilium runs. The socle, not AWS, tracks which CoreDNS
version runs on which Kubernetes minor. The foundations create no add-on
at all, and each driver's IAM role is written beside its add-on, outside the
path Crossplane may write to
([AWS-18](#aws-18-crossplanes-identity-and-its-permissions-boundary-in-the-foundations)).
The order is [SOCLE-02](socle.md#socle-02-cilium-and-coredns-before-flux-from-the-bootstrap).

**Sources.** [CreateCluster, `bootstrapSelfManagedAddons`](https://docs.aws.amazon.com/eks/latest/APIReference/API_CreateCluster.html) ·
[Update an add-on](https://docs.aws.amazon.com/eks/latest/userguide/updating-an-add-on.html) ·
[Cilium kube-proxy-free](https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/) ·
[Cilium EKS requirements](https://docs.cilium.io/en/stable/installation/requirements-eks/) ·
[`aws_eks_addon`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_addon).

## AWS-03: Pod Identity, not IRSA

**accepted** · 2026-09-08 · [`opentofu/aws/iam.tf`](../../opentofu/aws/iam.tf)

**Context.** EKS gives pods AWS credentials through IRSA (an OIDC provider
per cluster, a trust policy naming it) or through EKS Pod Identity (an agent
on each node, an association per service account). Pod Identity is AWS's
recommendation; its restriction to EC2 nodes matches the socle, which runs
no Fargate. Crossplane's AWS providers, both CSI drivers, the Load Balancer
Controller and Karpenter support it.

**Decision.** Pod Identity only. The module creates no IAM OIDC provider and
has no IRSA toggle. Every role trusts `pods.eks.amazonaws.com` with
`sts:AssumeRole` and `sts:TagSession`.

**Consequences.** The Pod Identity Agent add-on must run before anything
that needs an identity: the bootstrap module installs it before the Flux
Operator, because without it the associations hang without an error. The
cluster's OIDC issuer URL is still an output, for a consumer that wants it;
nothing in the socle uses it.

**Sources.** [EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html) ·
[Upbound AWS provider, Pod Identity](https://docs.upbound.io/manuals/packages/providers/aws-auth/aws-pod-identity/) ·
[Karpenter getting started](https://karpenter.sh/docs/getting-started/getting-started-with-karpenter/).

## AWS-04: Upgrade Insights as a pipeline pre-check

**proposed** · 2026-09-08 · [`opentofu/aws/cluster.tf`](../../opentofu/aws/cluster.tf), [`opentofu/aws/variables.tf`](../../opentofu/aws/variables.tf)

**Context.** EKS Upgrade Insights reports a cluster's use of APIs the next
version removes. It is the only check that sees the client's own workloads.
It reads 30 days of audit logs, so it misses an API called less than once a
month and keeps reporting a fixed one for up to 30 days
([containers-roadmap#2569](https://github.com/aws/containers-roadmap/issues/2569)).
AWS's blocking of `UpdateClusterVersion` on an `ERROR` finding was rolled
back, so an apply proceeds whatever the insights say.

**Decision.** The version pipeline calls `list-insights` before every
upgrade and stops on an `ERROR` finding. It is required, and never the only
check. `force_update_version` (default `false`) is the override.

**Consequences.** Built: the `force_update_version` variable. Not built: the
pipeline that calls `list-insights`. Until it exists, nothing stops an
upgrade on a finding.

**Sources.** [`list-insights`](https://docs.aws.amazon.com/cli/latest/reference/eks/list-insights.html) ·
[Upgrade Insights enforcement announcement](https://aws.amazon.com/about-aws/whats-new/2025/03/amazon-eks-enforces-upgrade-insights-check-cluster-upgrades) ·
[containers-roadmap#2570](https://github.com/aws/containers-roadmap/issues/2570) ·
[UpdateClusterVersion](https://docs.aws.amazon.com/eks/latest/APIReference/API_UpdateClusterVersion.html).

## AWS-05: Backup with Velero, not AWS Backup

**accepted** · 2026-09-08 · [`oci/catalog/velero`](../../oci/catalog/velero), [velero module](../catalog/velero.md)

**Context.** AWS Backup covers EKS clusters and their persistent storage,
with vault lock and cross-account copies. Velero does the same on every
cloud. Both snapshot the same EBS volumes, so the snapshot storage is the
same on either side.

**Decision.** Velero, as a catalog module. AWS Backup is not the default.

**Consequences.** One restore procedure, one failure mode and one rehearsal
on four clouds. The bucket and the module's IAM role are created by the
velero module through Crossplane, not by the foundations. EBS volumes are
backed up by CSI snapshots, which need the snapshot controller add-on
([AWS-02](#aws-02-vpc-cni-and-kube-proxy-refused-aws-only-add-ons-stay-eks-add-ons)).

**Sources.** [What is AWS Backup](https://docs.aws.amazon.com/aws-backup/latest/devguide/whatisbackup.html) ·
[AWS Backup pricing](https://aws.amazon.com/backup/pricing/) ·
[Velero](https://velero.io/docs/latest/).

## AWS-06: IPv6 refused

**accepted** · 2026-09-09 · [`opentofu/aws/variables.tf`](../../opentofu/aws/variables.tf)

**Context.** EKS's IPv6 mode is IPv6-only pods, chosen at cluster creation
and irreversible, and AWS documents it with the VPC CNI in prefix
delegation mode. Cilium's ENI IPv6 IPAM mode is beta
([cilium#18405](https://github.com/cilium/cilium/issues/18405)), and Cilium
cannot intercept IPv4 traffic over the `v4if0` interface EKS creates on IPv6
clusters ([cilium#28409](https://github.com/cilium/cilium/issues/28409)).

**Decision.** No IPv6 cluster, and no variable for one.

**Consequences.** Clusters are IPv4. Revisit when both Cilium issues close.

**Sources.** [EKS IPv6 clusters](https://docs.aws.amazon.com/eks/latest/userguide/cni-ipv6.html) ·
[EKS best practices, IPv6](https://aws.github.io/aws-eks-best-practices/networking/ipv6/).

## AWS-07: Security groups for pods refused

**accepted** · 2026-09-09 · [`opentofu/aws/cluster.tf`](../../opentofu/aws/cluster.tf)

**Context.** Security groups for pods is a VPC CNI feature (ENI trunking).
The socle does not run the VPC CNI
([AWS-02](#aws-02-vpc-cni-and-kube-proxy-refused-aws-only-add-ons-stay-eks-add-ons)).

**Decision.** Not offered.

**Consequences.** Pod-level network control is Cilium's network policy,
L3/L4 by identity and L7, the same on every cloud.

**Sources.** [Security groups for pods](https://docs.aws.amazon.com/eks/latest/userguide/security-groups-for-pods.html).

## AWS-08: Gateway API through the AWS Load Balancer Controller

**superseded by [GATEWAY-API-02](gateway-api.md#gateway-api-02-shared-public-and-private-gateways-on-cilium)** · 2026-09-09, superseded 2026-09-30 · [`opentofu/aws/certificate.tf`](../../opentofu/aws/certificate.tf)

**Context.** The AWS Load Balancer Controller implements Gateway API (GA in
v3.0.0), with an ALB for HTTP and an NLB for TCP.

**Decision.** It was to implement the socle's Gateway API on AWS: ALB by
default, NLB as a catalog option, WAF priced as its own line.

**Consequences.** Replaced when Cilium became the Gateway API
implementation on every cloud: the socle's two shared Gateways are served by
Cilium, behind NLBs that EKS's in-tree service controller creates from
annotations on the Service Cilium makes. The foundations provide only the
ACM certificate those NLBs terminate TLS with (`gateway_certificate`). No
Load Balancer Controller is installed.

**Sources.** [aws-load-balancer-controller v3.0.0](https://github.com/kubernetes-sigs/aws-load-balancer-controller/releases/tag/v3.0.0) ·
[aws-load-balancer-controller#4400](https://github.com/kubernetes-sigs/aws-load-balancer-controller/issues/4400).

## AWS-09: GuardDuty EKS Protection as a catalog option

**superseded by [AWS-14](#aws-14-guardduty-is-the-account-owners)** · 2026-09-09, superseded 2026-09-10

**Context.** GuardDuty EKS Protection has two sub-features priced
separately: Audit Log Monitoring and Runtime Monitoring.

**Decision.** It was to be a catalog option, off by default, priced through
rather than bundled.

**Consequences.** Dropped when the module was written: GuardDuty has one
detector per account and region, not per cluster, so a per-cluster toggle
cannot work.

**Sources.** [GuardDuty pricing](https://aws.amazon.com/guardduty/pricing/) ·
[GuardDuty EKS Runtime Monitoring](https://docs.aws.amazon.com/guardduty/latest/ug/eks-runtime-monitoring-guardduty.html).

## AWS-10: Secrets encrypted with KMS by default

**accepted** · 2026-09-09 · [`opentofu/aws/cluster.tf`](../../opentofu/aws/cluster.tf), [`opentofu/aws/variables.tf`](../../opentofu/aws/variables.tf)

**Context.** EKS envelope-encrypts Kubernetes Secrets with a KMS key when
given one. A key costs about $1 a month; requests cost next to nothing.

**Decision.** On by default (`secrets_encryption_enabled = true`). The module
creates its own key, with rotation, unless `secrets_encryption_kms_key_arn`
names one.

**Consequences.** One key per cluster. Turning it off is possible and is
the client's explicit choice.

**Sources.** [Enable KMS secrets encryption](https://docs.aws.amazon.com/eks/latest/userguide/enable-kms.html).

## AWS-11: Public API endpoint, restricted by CIDR, private access on

**accepted** · 2026-09-09 · [`opentofu/aws/cluster.tf`](../../opentofu/aws/cluster.tf), [`opentofu/aws/variables.tf`](../../opentofu/aws/variables.tf)

**Context.** The socle's apply and its pipelines reach the API server from
outside the VPC. A private-only endpoint moves that access into a bastion or
a VPN the module does not own. The endpoint toggles are free; the separate
EKS PrivateLink endpoint (about $0.01 an hour per AZ) serves the EKS API
itself, not the cluster.

**Decision.** `endpoint_public_access` and `endpoint_private_access` are both
on, with no variable. `cluster_endpoint_public_access_cidrs` is required,
with no default, and `0.0.0.0/0` is refused at plan.

**Consequences.** The runner that applies must be inside one of the CIDRs:
the helm provider talks to the API in the same apply. Nodes reach the API
privately.

**Sources.** [Cluster endpoint access control](https://docs.aws.amazon.com/eks/latest/userguide/config-cluster-endpoint.html) ·
[EKS interface endpoints](https://docs.aws.amazon.com/eks/latest/userguide/vpc-interface-endpoints.html).

## AWS-12: Reference network, public and private per AZ

**accepted** · 2026-09-09 · [`opentofu/aws/network.tf`](../../opentofu/aws/network.tf)

**Context.** ISO 27001 (A.8.22) and SOC 2 (CC6) expect demonstrated network
segmentation; a VPC with no private tier is a common audit finding. S3
gateway endpoints are free. Interface endpoints cost about $7.30 a month per
AZ each, a few dollars more than the same traffic through NAT at the volumes
a cluster's own AWS calls produce. A single NAT Gateway adds cross-AZ
transfer charges.

**Decision.** When the module creates the VPC: one public and one private
subnet per AZ, at least two AZs, no all-public option. One NAT Gateway and
one private route table per AZ. An S3 gateway endpoint, and interface
endpoints for `ecr.api`, `ecr.dkr`, `sts`, `ec2` and `logs` in the private
subnets. Nodes run in the private subnets.

**Consequences.** STS and EC2 calls, which Pod Identity and Cilium's ENI IPAM
depend on, stay off the NAT path. A VPC the client brings
(`create_vpc = false`) gets no endpoint and no flow log from the module.

**Sources.** [VPC pricing](https://aws.amazon.com/vpc/pricing/) ·
[PrivateLink pricing](https://aws.amazon.com/privatelink/pricing/) ·
[ISO 27001:2022 A.8.22](https://www.isms.online/iso-27001/annex-a-2022/8-22-segregation-of-networks-2022/) ·
[SOC 2 CC6](https://secureframe.com/hub/soc-2/common-criteria).

## AWS-13: Cloud resources observed from a central cluster

**proposed** · 2026-09-09

**Context.** AWS service metrics (RDS, ElastiCache, S3, SQS, SNS, Lambda, load
balancers, NAT, quotas) are free to ingest and billed on read,
`GetMetricData` at $0.01 per 1,000 metrics. For about 100 series, a
300-second interval costs about $8.64 a month, 60 seconds $43.20. CloudWatch
Metric Streams is cheaper only below about 190 seconds. Cost data is free to
export to the client's own bucket (CUR / Data Exports); the Cost Explorer
API is paid per request.

**Decision.** YACE in a central observability cluster reads service metrics
every 300 seconds; in-cluster metrics never take that path. Cost
attribution by CUR / Data Exports to the client's S3 bucket, on the socle's
cost-allocation tag. Unmanaged resources found through the Resource Groups
Tagging API; AWS Config as an option.

**Consequences.** Nothing is built: no YACE, no CUR export, no variable for
either. The in-cluster stack is
[SOCLE-03](socle.md#socle-03-one-in-cluster-monitoring-stack-on-every-cloud).

**Sources.** [`GetMetricData`](https://docs.aws.amazon.com/AmazonCloudWatch/latest/APIReference/API_GetMetricData.html) ·
[CloudWatch Metric Streams](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Metric-Streams.html) ·
[YACE](https://github.com/prometheus-community/yet-another-cloudwatch-exporter) ·
[AWS Data Exports](https://aws.amazon.com/about-aws/whats-new/2023/11/aws-billing-cost-management-data-exports) ·
[Cost allocation tags](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/cost-alloc-tags.html) ·
[Resource Groups Tagging API](https://docs.aws.amazon.com/resourcegroupstagging/latest/APIReference/Welcome.html).

## AWS-14: GuardDuty is the account owner's

**accepted** · 2026-09-10 · [`opentofu/aws/variables.tf`](../../opentofu/aws/variables.tf)

**Context.** GuardDuty has one detector per account and region. An account
commonly holds several clusters; two applies of the module would fight over
the same detector and its features.

**Decision.** The module has no GuardDuty variable and creates no detector.
GuardDuty, EKS Protection included, is configured by whoever owns the
account.

**Consequences.** A cluster is protected if, and only if, the account owner
turned GuardDuty on in its region. The socle neither checks nor reports it.

**Sources.** [GuardDuty pricing](https://aws.amazon.com/guardduty/pricing/).

## AWS-15: No extended support

**accepted** · 2026-09-10 · [`opentofu/aws/cluster.tf`](../../opentofu/aws/cluster.tf)

**Context.** A Kubernetes minor gets 14 months of standard support on EKS,
then 12 of extended support at six times the control plane rate. AWS's
default upgrade policy is `EXTENDED`, and a cluster in extended support
cannot leave it until it is upgraded.

**Decision.** `upgrade_policy.support_type = "STANDARD"`, hardcoded, with no
variable.

**Consequences.** At the end of standard support AWS upgrades the cluster
itself instead of billing extended support. The version policy
([SOCLE-05](socle.md#socle-05-the-kubernetes-version-moves-by-rings-n-1-then-n))
is meant to upgrade before that happens; this is the floor if it does not.

**Sources.** [EKS Kubernetes versions](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html) ·
[EKS pricing](https://aws.amazon.com/eks/pricing/).

## AWS-16: The account keeps custody of the logs

**accepted** · 2026-09-10 · [`opentofu/aws/cluster.tf`](../../opentofu/aws/cluster.tf), [`opentofu/aws/network.tf`](../../opentofu/aws/network.tf)

**Context.** The control plane's audit and authenticator logs are the record
of who did what to the API server, which ISO 27001 A.8.15 and SOC 2 CC7
expect. Flow logs are the record of which address reached which. A log group
that EKS or flow logs create implicitly never expires. CloudWatch Logs
encrypts with an AWS-owned key unless given one.

**Decision.** The module creates both log groups itself
(`/aws/eks/<cluster>/cluster`, `/aws/vpc/<cluster>/flow-logs`), with
`log_retention_days` (default 90) and one customer-managed KMS key, rotated,
scoped to this account's log groups. All five control-plane log types are on
by default (`cluster_log_types`). VPC flow logs record all traffic, in
ten-minute windows (`vpc_flow_logs_enabled`, default `true`).

**Consequences.** One more KMS key per cluster. Trimming `cluster_log_types`
cuts ingestion cost; an empty list turns control-plane logging off.

**Sources.** [EKS control plane logs](https://docs.aws.amazon.com/eks/latest/userguide/control-plane-logs.html) ·
[Encrypt log data with KMS](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/encrypt-log-data-kms.html).

## AWS-17: A bootstrap node group of two Spot nodes

**accepted** · 2026-09-24 · [`opentofu/aws/nodes.tf`](../../opentofu/aws/nodes.tf), [`opentofu/aws/variables.tf`](../../opentofu/aws/variables.tf)

**Context.** Karpenter is a pod and needs a node before it can provision
one. Cilium's operator, CoreDNS and Flux need one too. One instance type on
Spot is one capacity pool per AZ, and a reclaim can take both nodes at once.

**Decision.** The foundations own one managed node group, the bootstrap
group: `bootstrap_node_count = 2`, nothing scales it; `SPOT` over six
Graviton families of 4 vCPU (`t4g`, `m7g`, `m6g`, `c7g`, `c6g`, `r6g`,
`xlarge`); untainted; AL2023, IMDSv2 with one hop, a 20 GiB encrypted gp3
root volume, in the private subnets, rolled one node at a time.
`bootstrap_node_capacity_type = "ON_DEMAND"` takes the first type.

**Consequences.** Each type alone carries the socle with half its CPU free,
so losing a node to a reclaim is routine: EKS launches the replacement before
it drains the old node. Until Karpenter exists, every workload runs on these
two nodes. About $84 a month on Spot, $223 on demand, eu-west-3, September
2026 ([cost](../clouds/aws/index.md#cost)).

**Sources.** [Managed node groups, Spot](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html#managed-node-group-capacity-types) ·
[Spot Instance Advisor](https://aws.amazon.com/ec2/spot/instance-advisor/).

## AWS-18: Crossplane's identity and its permissions boundary in the foundations

**accepted** · 2026-09-24 · [`opentofu/aws/iam.tf`](../../opentofu/aws/iam.tf)

**Context.** Every catalog module declares its own cloud access, which
Crossplane turns into an IAM role
([SOCLE-04](socle.md#socle-04-each-module-owns-its-cloud-access-the-foundations-never-change)).
Something has to create Crossplane's own role. Its service account is known
before the cluster has a node: the socle runs every AWS provider pod as
`crossplane-system/provider-aws`. An identity that creates IAM roles is the
most powerful thing in the cluster.

**Decision.** With `crossplane` set, the foundations create a role
`<cluster>-crossplane`, its Pod Identity association, and a permissions
boundary `<cluster>-crossplane-boundary`. The role may create, write and
delete roles only under `/socle/<cluster>/` and only with that boundary;
pass them only to `pods.eks.amazonaws.com`; manage Pod Identity associations
on this cluster only; and create and configure, never delete, S3 buckets
named `<cluster>-*`. The boundary allows the services listed in
`crossplane.allowed_services` (empty by default) and always denies `iam`,
`sts`, `organizations`, `account`, `sso` and `identitystore`.

**Consequences.** A new module needs no change to the foundations; a module
that uses a new AWS service needs one word in the client's
`allowed_services`. No role Crossplane makes can do more than the boundary.
A role's trust policy cannot be bounded: a compromised Crossplane could make
a role, within the boundary, that another principal may assume. The
principal that applies needs `iam:CreatePolicy`. The client root passes the
boundary's ARN into `kube.crossplane` itself.

**Sources.** [Permissions boundaries](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_boundaries.html) ·
[EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html) ·
[crossplane module](../catalog/crossplane.md).
