---
title: GCP · GKE
description: What the socle builds on GCP, the decisions behind it, what it costs and what is proven.
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

## The decisions

All in [GCP decisions](../../decisions/gcp.md). The Kubernetes version policy
is the socle's:
[SOCLE-05](../../decisions/socle.md#socle-05-the-kubernetes-version-moves-by-rings-n-1-then-n).

- [GCP-01](../../decisions/gcp.md#gcp-01-autopilot-only-no-cluster-mode-option) · accepted · Autopilot only
- [GCP-02](../../decisions/gcp.md#gcp-02-regular-release-channel-rings-ordered-by-the-maintenance-window) · accepted · Regular channel, rings ordered by the maintenance window
- [GCP-03](../../decisions/gcp.md#gcp-03-only-the-free-system-metrics-auto-monitoring-refused) · accepted · only the free system metrics
- [GCP-04](../../decisions/gcp.md#gcp-04-workload-metrics-on-managed-service-for-prometheus) · superseded by SOCLE-03 · workload metrics on Managed Prometheus
- [GCP-05](../../decisions/gcp.md#gcp-05-velero-by-default-backup-for-gke-as-a-priced-option) · proposed · Velero by default, Backup for GKE as an option
- [GCP-06](../../decisions/gcp.md#gcp-06-workload-identity-federation-a-google-service-account-per-kubernetes-service-account) · accepted · Workload Identity Federation
- [GCP-07](../../decisions/gcp.md#gcp-07-dataplane-v2-and-plain-networkpolicy) · accepted · Dataplane V2 and plain NetworkPolicy
- [GCP-08](../../decisions/gcp.md#gcp-08-exposure-through-gkes-gateway-controller) · accepted · exposure through GKE's Gateway controller
- [GCP-09](../../decisions/gcp.md#gcp-09-private-nodes-a-dns-endpoint-and-a-sized-reference-network) · accepted · private nodes, DNS endpoint, sized network
- [GCP-10](../../decisions/gcp.md#gcp-10-subnet-flow-logs-on-at-half-sampling-over-ten-minutes) · accepted · subnet flow logs at half sampling
- [GCP-11](../../decisions/gcp.md#gcp-11-service-metrics-read-every-300-s-cloud-monitoring-alert-policies-refused) · proposed · service metrics every 300 s, no alert policies
- [GCP-12](../../decisions/gcp.md#gcp-12-cost-attribution-through-the-detailed-billing-export) · accepted · cost attribution through the billing export
- [GCP-13](../../decisions/gcp.md#gcp-13-crossplane-not-config-connector) · proposed · Crossplane, not Config Connector

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
- Per-decision figures are in [the GCP decisions](../../decisions/gcp.md).

</details>

## Status

- **Built**: the foundations module. No `opentofu/clusters/gcp` root: you
  write it, as the [quickstart](../../getting-started/gcp.md) shows.
- **Proven in CI**: a plan against floci-gcp, which runs no Compute Engine
  API. Never applied on a real project; catalog convergence on Autopilot
  unproven.
- **Not offered yet**: Velero, Crossplane providers, `kube.keda.services`,
  the shared Gateways ([limits](limits.md)).
