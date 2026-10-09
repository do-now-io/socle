---
title: AWS · EKS
description: What the socle builds on AWS, what is decided for you, what it costs, and what is proven.
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
  the Upgrade Insights pre-check, cloud-resource observability.
