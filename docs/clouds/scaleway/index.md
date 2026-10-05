---
title: Scaleway · Kapsule
description: What the socle builds on Scaleway, the decisions behind it, and what it costs.
sidebar:
  label: Overview
  order: 0
---

## What the socle builds

[`opentofu/scaleway`](../../../opentofu/scaleway/README.md) is one flat module. In one Scaleway Project it creates:

- a VPC (or attaches to yours) and one /22 Private Network for the cluster;
- one Public Gateway per zone the pools span, each with a reserved flexible IP: the nodes' only way out, and the cluster's stable source address;
- a Kapsule cluster, its control plane tier derived from `environment`, its API server reachable only from the CIDRs you list;
- one autoscaled node pool per zone, each in its own placement group and security group, with no public IP on any node;
- an IAM application, policy and API key for the in-cluster Crossplane provider, scoped to the Project and bound to the gateways' addresses;
- a query-only Cockpit token for Scaleway's own metrics and logs.

The [bootstrap](../../../opentofu/bootstrap/README.md), with `cloud = "scaleway"`, then installs Flux and the catalog on that cluster. It installs no Cilium and no CoreDNS here: Kapsule operates both. The [quickstart](../../getting-started/scaleway.md) walks through the two steps.

## The decisions

- **accepted** · [SCALEWAY-01: Kapsule, not Kosmos](../../decisions/scaleway.md#scaleway-01-kapsule-not-kosmos)
- **accepted** · [SCALEWAY-02: A dedicated control plane in production, mutualized elsewhere](../../decisions/scaleway.md#scaleway-02-a-dedicated-control-plane-in-production-mutualized-elsewhere)
- **accepted** · [SCALEWAY-03: Kapsule's own Cilium](../../decisions/scaleway.md#scaleway-03-kapsules-own-cilium)
- **accepted** · [SCALEWAY-04: COMPUTE3-X pools in two zones, under the cluster-autoscaler](../../decisions/scaleway.md#scaleway-04-compute3-x-pools-in-two-zones-under-the-cluster-autoscaler)
- **accepted** · [SCALEWAY-05: An explicit version, patches in a required window](../../decisions/scaleway.md#scaleway-05-an-explicit-version-patches-in-a-required-window)
- **accepted** · [SCALEWAY-06: Full isolation behind one Public Gateway per zone](../../decisions/scaleway.md#scaleway-06-full-isolation-behind-one-public-gateway-per-zone)
- **accepted** · [SCALEWAY-07: Add-ons and load balancers delegated, Load Balancer certificates refused](../../decisions/scaleway.md#scaleway-07-add-ons-and-load-balancers-delegated-load-balancer-certificates-refused)
- **accepted** · [SCALEWAY-08: One Project per environment, one scoped Crossplane key](../../decisions/scaleway.md#scaleway-08-one-project-per-environment-one-scoped-crossplane-key)
- **proposed** · [SCALEWAY-09: DNS and certificates through External-DNS and the Scaleway webhook](../../decisions/scaleway.md#scaleway-09-dns-and-certificates-through-external-dns-and-the-scaleway-webhook)
- **proposed** · [SCALEWAY-10: Backup with Velero into Object Storage](../../decisions/scaleway.md#scaleway-10-backup-with-velero-into-object-storage)
- **accepted** · [SCALEWAY-11: Workload metrics stay in the cluster, never pushed to Cockpit](../../decisions/scaleway.md#scaleway-11-workload-metrics-stay-in-the-cluster-never-pushed-to-cockpit)
- **accepted** · [SCALEWAY-12: A query-only Cockpit token](../../decisions/scaleway.md#scaleway-12-a-query-only-cockpit-token)
- **proposed** · [SCALEWAY-13: Scaleway's own signals, federated, costed per Project](../../decisions/scaleway.md#scaleway-13-scaleways-own-signals-federated-costed-per-project)
- **proposed** · [SCALEWAY-14: Crossplane through Scaleway's own provider, pinned, with a regenerable fork](../../decisions/scaleway.md#scaleway-14-crossplane-through-scaleways-own-provider-pinned-with-a-regenerable-fork)

## Cost

One cluster at the module's defaults, in fr-par: `availability_zones = ["fr-par-1", "fr-par-2"]`, `pool_min_size = 2` per zone, `node_type = "COMPUTE3-X8C-16G"`, `root_volume_size_in_gb = 100`, `public_gateway_type = "VPC-GW-S"`. Kapsule bills the nodes, not the Pods' requests, so these are floors: every environment runs at least 4 nodes and 2 gateways.

| Per month, EUR excl. VAT | dev or staging | prod |
| --- | ---: | ---: |
| 4 nodes, `COMPUTE3-X8C-16G` at €0.2341 an hour | 683.57 | 683.57 |
| 4 root volumes, 100 GB at the Block Storage 5K rate of €0.00013 per GB-hour | 37.96 | 37.96 |
| 2 Public Gateways `VPC-GW-S` at €0.026 an hour, and their 2 IPs at €0.005 an hour | 45.26 | 45.26 |
| Control plane: mutualized, or Dedicated 4 at €0.11 an hour | 0.00 | 80.30 |
| **Total at `pool_min_size`** | **766.79** | **847.09** |
| *At `pool_max_size = 5`: 10 nodes and 10 root volumes* | *1,849.09* | *1,929.39* |

List prices read from Scaleway's Instances and product catalog APIs on 2026-10-05, at 730 hours a month. Not included: Load Balancers, which the cloud controller manager creates per Service of type `LoadBalancer` (the socle creates none on Scaleway, having no Gateway API implementation here), block volumes claimed by workloads, Object Storage for state, and traffic. Cockpit adds nothing while nothing is pushed to it ([SCALEWAY-11](../../decisions/scaleway.md#scaleway-11-workload-metrics-stay-in-the-cluster-never-pushed-to-cockpit)). There is no spot market; savings plans are the only discount, at an unpublished rate.

`pool_min_size` is the lever: `pool_min_size = 1` halves the node lines, at the cost of one node per zone.

## Status

The module is plan-only in CI: Scaleway has no emulator, so `tofu test` and a `tofu plan` of [`examples/minimal`](../../../opentofu/scaleway/examples/minimal/README.md) run with fixture credentials and make no API call. No apply has been proven by the socle's CI. The repository has no `opentofu/clusters/scaleway` root.

In the catalog, Scaleway gets every module except Velero. Gateway API installs its CRDs and nothing implements them, so no shared Gateway exists and no module gets a route. Crossplane installs with no Scaleway provider. What else is missing is in [limits](limits.md).
