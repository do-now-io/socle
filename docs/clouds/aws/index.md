---
title: AWS · EKS
description: What the socle builds on AWS, the decisions behind it, what it costs, and what is proven.
sidebar:
  label: Overview
  order: 0
---

## What the socle builds

One `tofu apply` of [`opentofu/clusters/aws`](../../../opentofu/clusters/aws)
builds, in your account, a VPC (public and private subnets per AZ, NAT,
endpoints, flow logs), an EKS Standard cluster with no VPC CNI, kube-proxy or
CoreDNS add-on, two Spot Graviton bootstrap nodes, and on request
Crossplane's IAM role and the Gateways' ACM certificate. It then installs
Cilium, CoreDNS, the EKS add-ons and the Flux Operator, and Flux renders the
catalog from the signed artifact.

Start with [Prerequisites](prerequisites.md), then the
[AWS quickstart](../../getting-started/aws.md). What is decided for you is in
[Foundations](foundations.md).

## The decisions

All in [AWS decisions](../../decisions/aws.md). The Kubernetes version policy
is the socle's:
[SOCLE-05](../../decisions/socle.md#socle-05-the-kubernetes-version-moves-by-rings-n-1-then-n).

- [AWS-01](../../decisions/aws.md#aws-01-eks-standard-not-auto-mode) · accepted · EKS Standard, not Auto Mode
- [AWS-02](../../decisions/aws.md#aws-02-vpc-cni-and-kube-proxy-refused-aws-only-add-ons-stay-eks-add-ons) · accepted · no VPC CNI or kube-proxy; AWS-only add-ons stay EKS add-ons
- [AWS-03](../../decisions/aws.md#aws-03-pod-identity-not-irsa) · accepted · Pod Identity, not IRSA
- [AWS-04](../../decisions/aws.md#aws-04-upgrade-insights-as-a-pipeline-pre-check) · proposed · Upgrade Insights as a pipeline pre-check
- [AWS-05](../../decisions/aws.md#aws-05-backup-with-velero-not-aws-backup) · accepted · Velero, not AWS Backup
- [AWS-06](../../decisions/aws.md#aws-06-ipv6-refused) · accepted · IPv6 refused
- [AWS-07](../../decisions/aws.md#aws-07-security-groups-for-pods-refused) · accepted · security groups for pods refused
- [AWS-08](../../decisions/aws.md#aws-08-gateway-api-through-the-aws-load-balancer-controller) · superseded by [GATEWAY-API-02](../../decisions/gateway-api.md#gateway-api-02-shared-public-and-private-gateways-on-cilium) · Gateway API through the AWS Load Balancer Controller
- [AWS-09](../../decisions/aws.md#aws-09-guardduty-eks-protection-as-a-catalog-option) · superseded by AWS-14 · GuardDuty as a catalog option
- [AWS-10](../../decisions/aws.md#aws-10-secrets-encrypted-with-kms-by-default) · accepted · Secrets encrypted with KMS by default
- [AWS-11](../../decisions/aws.md#aws-11-public-api-endpoint-restricted-by-cidr-private-access-on) · accepted · public endpoint restricted by CIDR, private access on
- [AWS-12](../../decisions/aws.md#aws-12-reference-network-public-and-private-per-az) · accepted · public and private subnets per AZ
- [AWS-13](../../decisions/aws.md#aws-13-cloud-resources-observed-from-a-central-cluster) · proposed · cloud resources observed from a central cluster
- [AWS-14](../../decisions/aws.md#aws-14-guardduty-is-the-account-owners) · accepted · GuardDuty is the account owner's
- [AWS-15](../../decisions/aws.md#aws-15-no-extended-support) · accepted · no extended support
- [AWS-16](../../decisions/aws.md#aws-16-the-account-keeps-custody-of-the-logs) · accepted · the account keeps custody of the logs
- [AWS-17](../../decisions/aws.md#aws-17-a-bootstrap-node-group-of-two-spot-nodes) · accepted · two Spot bootstrap nodes
- [AWS-18](../../decisions/aws.md#aws-18-crossplanes-identity-and-its-permissions-boundary-in-the-foundations) · accepted · Crossplane's identity and boundary in the foundations

## Cost

One cluster, defaults, two AZs. US dollars, eu-west-3 list prices,
September 2026, 730 hours a month.

| Line | Per month |
| --- | --- |
| EKS control plane, standard support | $73 |
| Two Spot bootstrap nodes and their volumes | about $84 |
| Interface endpoints, five services in two AZs | about $73 |
| KMS keys | about $2 |
| **Total, before NAT and traffic** | **about $232** |

<details>
<summary>Under the hood</summary>

- The node line reaches $123 when both nodes come from `r6g`.
  `bootstrap_node_capacity_type = "ON_DEMAND"` puts it at $223 (two
  `t4g.xlarge`).
- Spot, per node: `t4g.xlarge` $39.42, `m6g.xlarge` $40.37, `m7g.xlarge`
  $41.68, `c6g.xlarge` $42.63, `r6g.xlarge` $59.57; `c7g.xlarge` was not
  priced. Each node has a 20 GiB gp3 volume.
- Interface endpoints: about $7.30 each per AZ. Each extra AZ adds one per
  service and a NAT Gateway.
- Not counted, because they depend on use: the NAT Gateways (one per AZ,
  hourly plus per GB), the Gateways' NLBs when `gateway_certificate` is set,
  CloudWatch Logs ingestion and storage, EBS volumes and snapshots, and the
  workloads' own nodes.

</details>

## Status

- **Built**: the foundations ([`opentofu/aws`](../../../opentofu/aws)) and
  the one-apply root.
- **Proven in CI**: static checks on every pull request
  ([`pr-static.yaml`](../../../.github/workflows/pr-static.yaml)), a plan
  against floci ([`integration.yaml`](../../../.github/workflows/integration.yaml)),
  and, on every published artifact, the real root applied on floci's k3s,
  every module checked by Chainsaw, then uninstalled and destroyed
  ([`e2e.yaml`](../../../.github/workflows/e2e.yaml)). Not proven: Cilium on
  real nodes, Pod Identity, IAM enforcement, ACM, Route 53, the NLBs.
- **Not built**: Karpenter ([#53](https://github.com/do-now-io/socle/issues/53)),
  the Upgrade Insights pre-check (AWS-04), cloud-resource observability
  (AWS-13).
