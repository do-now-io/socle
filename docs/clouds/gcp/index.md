---
title: GCP · GKE
description: What the socle builds on GCP, and the decisions behind it.
sidebar:
  label: Overview
  order: 0
---

On Google Cloud the socle runs on a GKE Autopilot cluster that the
[foundations module](foundations.md) creates in your project. The
[bootstrap module](../../reference/opentofu-modules.md) then installs Flux on
it, and Flux pulls the catalog.

## What the socle builds

- A regional GKE Autopilot cluster on the Regular release channel, with a
  maintenance window you choose.
- A custom-mode VPC (or your existing one), one subnetwork with a Pod range,
  a proxy-only subnetwork, a Cloud Router and Cloud NAT.
- Private nodes, and the control plane reached only through its DNS-based
  endpoint, authorised by IAM.
- GKE's Gateway API controller and its standard-channel CRDs.
- A Pub/Sub topic for GKE upgrade notifications.
- GKE cost allocation, and optionally the BigQuery dataset for the detailed
  billing export.
- No key and no credential: workloads authenticate through Workload Identity
  Federation, which Autopilot enforces.

On that cluster the catalog offers every module except `gateway_api` and
`velero`. Dataplane V2 is GKE's, so the bootstrap installs no Cilium.

## The decisions

- [GCP-01](../../decisions/gcp.md#gcp-01-autopilot-only-no-cluster-mode-option) — accepted: Autopilot only, no cluster mode option.
- [GCP-02](../../decisions/gcp.md#gcp-02-regular-release-channel-rings-ordered-by-the-maintenance-window) — accepted: Regular release channel, rings ordered by the maintenance window.
- [GCP-03](../../decisions/gcp.md#gcp-03-only-the-free-system-metrics-auto-monitoring-refused) — accepted: only the free system metrics, Auto-Monitoring refused.
- [GCP-04](../../decisions/gcp.md#gcp-04-workload-metrics-on-managed-service-for-prometheus) — superseded by SOCLE-03: workload metrics on Managed Service for Prometheus.
- [GCP-05](../../decisions/gcp.md#gcp-05-velero-by-default-backup-for-gke-as-a-priced-option) — proposed: Velero by default, Backup for GKE as a priced option.
- [GCP-06](../../decisions/gcp.md#gcp-06-workload-identity-federation-a-google-service-account-per-kubernetes-service-account) — accepted: Workload Identity Federation, a Google service account per Kubernetes service account.
- [GCP-07](../../decisions/gcp.md#gcp-07-dataplane-v2-and-plain-networkpolicy) — accepted: Dataplane V2 and plain NetworkPolicy.
- [GCP-08](../../decisions/gcp.md#gcp-08-exposure-through-gkes-gateway-controller) — accepted: exposure through GKE's Gateway controller.
- [GCP-09](../../decisions/gcp.md#gcp-09-private-nodes-a-dns-endpoint-and-a-sized-reference-network) — accepted: private nodes, a DNS endpoint, and a sized reference network.
- [GCP-10](../../decisions/gcp.md#gcp-10-subnet-flow-logs-on-at-half-sampling-over-ten-minutes) — accepted: subnet flow logs on, at half sampling over ten minutes.
- [GCP-11](../../decisions/gcp.md#gcp-11-service-metrics-read-every-300-s-cloud-monitoring-alert-policies-refused) — proposed: service metrics read every 300 s, Cloud Monitoring alert policies refused.
- [GCP-12](../../decisions/gcp.md#gcp-12-cost-attribution-through-the-detailed-billing-export) — accepted: cost attribution through the detailed billing export.
- [GCP-13](../../decisions/gcp.md#gcp-13-crossplane-not-config-connector) — proposed: Crossplane, not Config Connector.

The Kubernetes version policy across clouds is
[SOCLE-05](../../decisions/socle.md#socle-05-the-kubernetes-version-moves-by-rings-n-1-then-n).

## Cost

Autopilot bills Pod resource requests, not nodes. The figures are in USD, at
us-central1 list price (Autopilot rates are not published per region), read
on 8 September 2026, for a reference estate of three clusters: prod with
20 vCPU / 40 GiB of Pod requests, staging 8 / 16, dev 4 / 8.

| | Per month |
| --- | --- |
| Clusters and Pod requests | $1,488 |
| Network: three load balancers, three Cloud NAT gateways, data processing | $96 |
| Cloud Logging, 30 GiB per cluster | $20 |
| **Total** | **$1,604** |

Not in the total: the Pod requests of the catalog modules you enable,
including the in-cluster monitoring stack, which add to the first line;
subnet flow logs, about a dollar a cluster; and Backup for GKE, $9 per
protected namespace, if you turn it on. The per-decision figures are in
[the GCP decisions](../../decisions/gcp.md).

## Status

- The module plans in CI against the floci-gcp emulator, which implements no
  Compute Engine API. No socle cluster has been applied on a real GCP project
  from CI, and the catalog has not been proven to converge on Autopilot.
- There is no `opentofu/clusters/gcp` root: you write the root that calls the
  foundations and the bootstrap, as the [quickstart](../../getting-started/gcp.md)
  shows.
- Not offered on GCP yet: Velero, Crossplane providers, and
  `kube.keda.services`. See [limits](limits.md).
