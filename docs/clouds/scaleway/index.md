---
title: Scaleway · Kapsule
description: What the socle builds on Scaleway, what is decided for you, what it costs and what is proven.
sidebar:
  label: Overview
  order: 0
---

## What the socle builds

[`opentofu/scaleway`](../../../opentofu/scaleway/README.md) builds, in one
Project, a /22 Private Network, a Public Gateway per zone (the nodes' only
way out), a Kapsule cluster whose API server answers only the CIDRs you list,
one autoscaled pool per zone with no public IP, a scoped Crossplane key and a
query-only Cockpit token. The [bootstrap](../../../opentofu/bootstrap/README.md)
then installs Flux and the catalog; Kapsule operates Cilium and CoreDNS.

Start with [Prerequisites](prerequisites.md), then the
[Scaleway quickstart](../../getting-started/scaleway.md). What is decided for
you is in [Foundations](foundations.md).

## Cost

One cluster at the defaults (two zones, 2 nodes per zone, `COMPUTE3-X8C-16G`).
Euros excluding VAT, fr-par list prices, 2026-10-05, 730 hours a month.

| Per month | dev or staging | prod |
| --- | ---: | ---: |
| 4 nodes, root volumes, 2 Public Gateways and their IPs | 766.79 | 766.79 |
| Control plane: mutualized, or Dedicated 4 | 0.00 | 80.30 |
| **Total at `pool_min_size`** | **766.79** | **847.09** |
| *At `pool_max_size = 5`* | *1,849.09* | *1,929.39* |

<details>
<summary>Under the hood</summary>

| Line | Per month |
| --- | ---: |
| 4 nodes at €0.2341 an hour | 683.57 |
| 4 root volumes of 100 GB at €0.00013 per GB-hour (Block Storage 5K) | 37.96 |
| 2 `VPC-GW-S` at €0.026 an hour, 2 IPs at €0.005 an hour | 45.26 |
| Dedicated 4 control plane at €0.11 an hour | 80.30 |

- Kapsule bills nodes, not requests: every environment runs at least 4 nodes
  and 2 gateways. `pool_min_size = 1` halves the node lines.
- Not included: Load Balancers (one per Service of type `LoadBalancer`),
  workload volumes, Object Storage for state, traffic. Cockpit adds nothing
  while nothing is pushed to it.
- No spot market; savings plans are the only discount, rate unpublished.
- Prices read from Scaleway's Instances and product catalog APIs.

</details>

## Status

- **Built**: the foundations module. No `opentofu/clusters/scaleway` root:
  you write it, as the [quickstart](../../getting-started/scaleway.md) shows.
- **Proven in CI**: plan only, with fixture credentials; Scaleway has no
  emulator. No apply proven.
- **Not offered yet**: Velero, a Gateway API implementation (no shared
  Gateway, no route), a Crossplane Scaleway provider ([limits](limits.md)).
