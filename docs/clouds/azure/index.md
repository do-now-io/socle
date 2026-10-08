---
title: Azure · AKS
description: What the socle builds on Azure, what is decided for you, what it costs and what is proven.
sidebar:
  label: Overview
  order: 0
---

## What the socle builds

Two applies, no one-apply root yet.
[`opentofu/azure`](../../../opentofu/azure/main.tf) builds a resource group, a
VNet with a NAT gateway, and a private AKS Standard cluster with Node
Auto-Provisioning, no CNI, Entra Workload ID and a two-node `system` pool.
[`opentofu/bootstrap`](../../../opentofu/bootstrap/main.tf) with
`cloud = "azure"` then installs Cilium (BYO CNI) and Flux, and Flux renders
the catalog. The shared Gateways run on Cilium.

Start with [Prerequisites](prerequisites.md), then the
[Azure quickstart](../../getting-started/azure.md). What is decided for you is
in [Foundations](foundations.md).

## Cost

Per cluster. US dollars, France Central list prices, September 2026, before
tax.

| Line | Per month |
| --- | --- |
| Control plane, Standard tier ($0.10/hour) | $73.00 |
| NAT gateway ($0.045/hour, plus $0.045/GB) | $32.85 |
| API server private endpoint ($0.01/hour, plus $0.01/GB) | $7.30 |
| Nodes | the VM price; NAP adds no meter |

<details>
<summary>Under the hood</summary>

- Reference estate (one prod 24/7, two UAT 12 hours per working day, one
  Standard_D4s_v5 and one Standard_D8s_v5 each): control plane and nodes
  $1,060.34 a month, against $1,338.99 on AKS Automatic.
- Not counted: the two `system` nodes (2 × Standard_D2s_v5), and the
  Container Insights and Managed Prometheus ingestion the module still turns
  on,
  billed per GB.

</details>

## Status

- **Built**: the foundations and the bootstrap's `azure` branch, both
  `tofu test`ed with mocked providers. The plan against floci-az fails on its
  self-signed certificate; not a required check.
- **Never applied** on a real subscription: BYO CNI with NAP, the private
  cluster and Cilium on AKS are unproven. Convergence is proven on AWS
  (floci) only.
- **Not offered yet**: Velero, a Crossplane Azure provider,
  `kube.keda.services` ([limits](limits.md)).
