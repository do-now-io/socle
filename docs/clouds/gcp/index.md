---
title: GCP · GKE
description: What the socle builds on GCP, what is decided for you, what it costs and what is proven.
sidebar:
  label: Overview
  order: 0
---

## What the socle builds

[`opentofu/gcp`](../../../opentofu/gcp/README.md) builds, in your project, a regional GKE
Autopilot cluster with private nodes and a DNS-only control plane endpoint, a
VPC (or yours) with Cloud NAT, GKE's Gateway API controller, an upgrade
notification topic and cost allocation. No key: workloads use Workload
Identity Federation. The [bootstrap](../../reference/opentofu-modules.md)
then installs Flux (no Cilium: Dataplane V2 is GKE's), and Flux renders the
catalog.

Start with [Prerequisites](prerequisites.md), then the
[GCP quickstart](../../getting-started/gcp.md). What is decided for you is in
[Foundations](foundations.md).

## Cost

Autopilot bills Pod requests, not nodes. US dollars, us-central1 list prices,
8 September 2026, three clusters: prod 20 vCPU / 40 GiB of requests, staging
8 / 16, dev 4 / 8.

| Line | Per month |
| --- | --- |
| Clusters and Pod requests | $1,488 |
| Three load balancers, three Cloud NAT gateways, data processing | $96 |
| Cloud Logging, 30 GiB per cluster | $20 |
| **Total** | **$1,604** |

<details>
<summary>Under the hood</summary>

- Autopilot rates are not published per region, hence us-central1.
- Not in the total: the Pod requests of the catalog modules you enable,
  monitoring included; subnet flow logs, about a dollar a cluster; Backup for
  GKE, $9 per protected namespace, if turned on.

</details>

## Status

- **Built**: the foundations module. No `opentofu/clusters/gcp` root: you
  write it, as the [quickstart](../../getting-started/gcp.md) shows.
- **Proven in CI**: a plan against floci-gcp, which runs no Compute Engine
  API. Never applied on a real project; catalog convergence on Autopilot
  unproven.
- **Not offered yet**: Velero, Crossplane providers, `kube.keda.services`,
  the shared Gateways ([limits](limits.md)).
