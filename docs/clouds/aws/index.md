---
title: AWS · EKS
description: What the socle builds on AWS, the decisions behind it, what it costs, and what is proven.
sidebar:
  label: Overview
  order: 0
---

## What the socle builds

One apply of [`opentofu/clusters/aws`](../../../opentofu/clusters/aws) builds,
in the client's account:

- a VPC with a public and a private subnet per AZ, a NAT Gateway per AZ, an
  S3 gateway endpoint and five interface endpoints, and VPC flow logs;
- an EKS Standard cluster with no VPC CNI, no kube-proxy and no CoreDNS
  add-on, Secrets encrypted with KMS, all five control-plane log types,
  a public endpoint restricted by CIDR and a private one;
- a bootstrap node group of two Spot Graviton nodes, the only compute until
  Karpenter exists;
- Cilium and CoreDNS by Helm, then the EKS add-ons (Pod Identity Agent, EBS
  CSI, snapshot controller, EFS CSI on request);
- optionally Crossplane's IAM role and its permissions boundary, and the
  ACM certificate of the two shared Gateways;
- the Flux Operator, which pulls the signed socle artifact and renders the
  catalog.

The foundations are described in [Foundations](foundations.md); the
prerequisites in [Prerequisites](prerequisites.md); a first cluster in the
[AWS quickstart](../../getting-started/aws.md).

## The decisions

Each one is a section of [AWS decisions](../../decisions/aws.md).

- [AWS-01](../../decisions/aws.md#aws-01-eks-standard-not-auto-mode): EKS Standard, not Auto Mode — accepted (self-hosted Karpenter not built, [#53](https://github.com/do-now-io/socle/issues/53))
- [AWS-02](../../decisions/aws.md#aws-02-vpc-cni-and-kube-proxy-refused-aws-only-add-ons-stay-eks-add-ons): VPC CNI and kube-proxy refused; AWS-only add-ons stay EKS add-ons — accepted
- [AWS-03](../../decisions/aws.md#aws-03-pod-identity-not-irsa): Pod Identity, not IRSA — accepted
- [AWS-04](../../decisions/aws.md#aws-04-upgrade-insights-as-a-pipeline-pre-check): Upgrade Insights as a pipeline pre-check — proposed
- [AWS-05](../../decisions/aws.md#aws-05-backup-with-velero-not-aws-backup): Backup with Velero, not AWS Backup — accepted
- [AWS-06](../../decisions/aws.md#aws-06-ipv6-refused): IPv6 refused — accepted
- [AWS-07](../../decisions/aws.md#aws-07-security-groups-for-pods-refused): Security groups for pods refused — accepted
- [AWS-08](../../decisions/aws.md#aws-08-gateway-api-through-the-aws-load-balancer-controller): Gateway API through the AWS Load Balancer Controller — superseded by [GATEWAY-API-02](../../decisions/gateway-api.md#gateway-api-02-shared-public-and-private-gateways-on-cilium)
- [AWS-09](../../decisions/aws.md#aws-09-guardduty-eks-protection-as-a-catalog-option): GuardDuty EKS Protection as a catalog option — superseded by AWS-14
- [AWS-10](../../decisions/aws.md#aws-10-secrets-encrypted-with-kms-by-default): Secrets encrypted with KMS by default — accepted
- [AWS-11](../../decisions/aws.md#aws-11-public-api-endpoint-restricted-by-cidr-private-access-on): Public API endpoint, restricted by CIDR, private access on — accepted
- [AWS-12](../../decisions/aws.md#aws-12-reference-network-public-and-private-per-az): Reference network, public and private per AZ — accepted
- [AWS-13](../../decisions/aws.md#aws-13-cloud-resources-observed-from-a-central-cluster): Cloud resources observed from a central cluster — proposed
- [AWS-14](../../decisions/aws.md#aws-14-guardduty-is-the-account-owners): GuardDuty is the account owner's — accepted
- [AWS-15](../../decisions/aws.md#aws-15-no-extended-support): No extended support — accepted
- [AWS-16](../../decisions/aws.md#aws-16-the-account-keeps-custody-of-the-logs): The account keeps custody of the logs — accepted
- [AWS-17](../../decisions/aws.md#aws-17-a-bootstrap-node-group-of-two-spot-nodes): A bootstrap node group of two Spot nodes — accepted
- [AWS-18](../../decisions/aws.md#aws-18-crossplanes-identity-and-its-permissions-boundary-in-the-foundations): Crossplane's identity and its permissions boundary in the foundations — accepted

The Kubernetes version policy is the socle's:
[SOCLE-05](../../decisions/socle.md#socle-05-the-kubernetes-version-moves-by-rings-n-1-then-n).

## Cost

What the socle itself costs on one cluster with the defaults and two AZs,
list prices in US dollars, eu-west-3, September 2026, per month of 730 hours:

| Line | Per month |
| --- | --- |
| EKS control plane, standard support | $73 |
| Bootstrap nodes, two on Spot, with their 20 GiB gp3 volumes | about $84 (up to $123 when both come from `r6g`) |
| Interface endpoints, five services in two AZs, at about $7.30 each per AZ | about $73 |
| KMS keys, Secrets and logs | about $2 |
| **Total, before NAT and traffic** | **about $232** |

`bootstrap_node_capacity_type = "ON_DEMAND"` puts the nodes at $223 (two
`t4g.xlarge`). Each extra AZ adds an interface endpoint per service and a
NAT Gateway.

Not counted, because they depend on the cluster's use: the NAT Gateways (one
per AZ, hourly plus per GB processed), the two Gateways' NLBs when
`gateway_certificate` is set, CloudWatch Logs ingestion and storage (control
plane and flow logs), EBS volumes and snapshots, and the workloads' own
nodes.

The bootstrap nodes per type, Spot, per node: `t4g.xlarge` $39.42,
`m6g.xlarge` $40.37, `m7g.xlarge` $41.68, `c6g.xlarge` $42.63, `r6g.xlarge`
$59.57; `c7g.xlarge` was not priced.

## Status

- **Foundations:** built, [`opentofu/aws`](../../../opentofu/aws).
- **One-apply root:** built, [`opentofu/clusters/aws`](../../../opentofu/clusters/aws):
  foundations, Cilium, CoreDNS, the EKS add-ons, Flux and the catalog in one
  `tofu apply`.
- **Proven in CI:** `tofu test`, tflint and Trivy on every pull request
  ([`pr-static.yaml`](../../../.github/workflows/pr-static.yaml)); a plan of
  the foundations against the floci emulator
  ([`integration.yaml`](../../../.github/workflows/integration.yaml)); and,
  on every published artifact, the real root applied once on floci's k3s,
  every module's health checked by Chainsaw, then the socle uninstalled and
  the cluster destroyed (the `root (aws)` job of
  [`e2e.yaml`](../../../.github/workflows/e2e.yaml)).
- **Not proven by CI:** what floci does not run — Cilium on real nodes, Pod
  Identity, IAM enforcement, ACM and Route 53, the NLBs. Those need a real
  AWS account.
- **Not built:** Karpenter ([#53](https://github.com/do-now-io/socle/issues/53)),
  the Upgrade Insights pre-check ([AWS-04](../../decisions/aws.md#aws-04-upgrade-insights-as-a-pipeline-pre-check)),
  cloud-resource observability ([AWS-13](../../decisions/aws.md#aws-13-cloud-resources-observed-from-a-central-cluster)).
