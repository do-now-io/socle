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
notification topic and cost allocation. No key and no Google service
account: every workload is a Workload Identity Federation principal of its
own, and Crossplane's grants are bounded by the roles you allow. With
`gateway_certificate`, Google-managed certificates for the shared Gateways.
The [bootstrap](../../reference/opentofu-modules.md) then installs Flux (no
Cilium: Dataplane V2 is GKE's), and Flux renders the catalog.
[`opentofu/clusters/gcp`](../../../opentofu/clusters/gcp/README.md) runs
both in one apply.

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

- **Built**: the foundations module and the
  [`opentofu/clusters/gcp`](../../../opentofu/clusters/gcp/README.md) root;
  on gcp the catalog offers every module but `metrics_server` (GKE serves
  `metrics.k8s.io` itself), with Crossplane's Cloud Platform and Storage
  providers, the shared Gateways, Velero and `kube.keda.services = ["pubsub"]`.
- **Proven**: in CI, a plan against floci-gcp; on every published artifact,
  the bootstrap module on floci-gcp's k3s, every module the gcp overlay
  offers converged and checked by Chainsaw, then uninstalled and destroyed
  ([`e2e.yaml`](../../../.github/workflows/e2e.yaml)); on a real GKE Autopilot sandbox project (2026-10-07, PR #84), the
  root applied, every catalog module converged, and destroyed in two runs;
  on 2026-10-16 (artifact `0.0.0-feat-gcp-parity.d896756`), every `platform: gke` test passed and
  Grafana answered over https, the modules turned on in four waves because a
  fresh project's quotas do not hold the whole catalog at once
  ([sizing](sizing.md#what-fits-a-fresh-project)).
- **Not offered yet**: what [limits](limits.md) lists.
