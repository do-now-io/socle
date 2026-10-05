---
title: Foundations
description: 'The GCP foundations module: what is decided for you, and its full reference.'
sidebar:
  order: 2
---

The module [`opentofu/gcp`](../../../opentofu/gcp/README.md) builds the network and
an empty Autopilot cluster, then steps away: the catalog arrives through the
bootstrap and Flux. Every default is a position from
[the GCP decisions](../../decisions/gcp.md); an option absent from the
interface is a refusal, not an oversight.

## What is decided for you

| Position | How | Decision |
| --- | --- | --- |
| Autopilot, no cluster mode option | enforced | [GCP-01](../../decisions/gcp.md#gcp-01-autopilot-only-no-cluster-mode-option) |
| Regular release channel; `EXTENDED` refused | default | [GCP-02](../../decisions/gcp.md#gcp-02-regular-release-channel-rings-ordered-by-the-maintenance-window) |
| Maintenance window, at least 4 hours, no default | required | [GCP-02](../../decisions/gcp.md#gcp-02-regular-release-channel-rings-ordered-by-the-maintenance-window) |
| Upgrade notifications to a Pub/Sub topic | default | [GCP-02](../../decisions/gcp.md#gcp-02-regular-release-channel-rings-ordered-by-the-maintenance-window) |
| Only the free system metric components; system and workload logs | default | [GCP-03](../../decisions/gcp.md#gcp-03-only-the-free-system-metrics-auto-monitoring-refused) |
| Backup for GKE agent off | default | [GCP-05](../../decisions/gcp.md#gcp-05-velero-by-default-backup-for-gke-as-a-priced-option) |
| Workload Identity pool and principal prefix as outputs | enforced by Autopilot | [GCP-06](../../decisions/gcp.md#gcp-06-workload-identity-federation-a-google-service-account-per-kubernetes-service-account) |
| Dataplane V2 and NetworkPolicy, as Autopilot sets them | enforced by Autopilot | [GCP-07](../../decisions/gcp.md#gcp-07-dataplane-v2-and-plain-networkpolicy) |
| GKE's Gateway API controller, standard channel | default | [GCP-08](../../decisions/gcp.md#gcp-08-exposure-through-gkes-gateway-controller) |
| Private nodes, flipping Autopilot's default; Cloud NAT | default | [GCP-09](../../decisions/gcp.md#gcp-09-private-nodes-a-dns-endpoint-and-a-sized-reference-network) |
| DNS-based control plane endpoint; IP endpoints off; no client certificate | default | [GCP-09](../../decisions/gcp.md#gcp-09-private-nodes-a-dns-endpoint-and-a-sized-reference-network) |
| Nodes `/22`, Pods `/16` (at least `/17`), proxy-only `/23` (at least `/26`), no Services range | default | [GCP-09](../../decisions/gcp.md#gcp-09-private-nodes-a-dns-endpoint-and-a-sized-reference-network) |
| Subnet flow logs at 0.5 sampling over 10 minutes | default | [GCP-10](../../decisions/gcp.md#gcp-10-subnet-flow-logs-on-at-half-sampling-over-ten-minutes) |
| GKE cost allocation on from creation | default | [GCP-12](../../decisions/gcp.md#gcp-12-cost-attribution-through-the-detailed-billing-export) |
| `owner`, `environment` and `socle-version` labels on every billable resource | enforced | — |
| Deletion protection on | default | — |

The network can be the module's (`create_network = true`) or yours
(`network_name`). In a Shared VPC where the network team owns subnets, set
`create_subnetwork = false` with `subnetwork_name` and `pod_range_name`, and
the plan stops asking for NAT on a subnetwork whose egress is someone
else's.

## What is deliberately absent

- **`EXTENDED` as a release channel**: Google forbids Autopilot clusters in
  it.
- **A Workload Identity toggle**: Autopilot enforces it.
- **A CNI or datapath variable, and Hubble**: Autopilot enforces Dataplane V2.
- **`master_authorized_networks` and `master_ipv4_cidr_block`**: they govern
  the IP endpoints this module disables.
- **A Services secondary range**: GKE assigns Service addresses from its own
  range on Autopilot 1.27 and later.
- **Auto IPAM**: in Preview when decided; a module default has to be GA.
- **Auto-Monitoring and `gke_auto_upgrade_config`**: silent recurring cost.
- **A Config Connector toggle**: Crossplane is the choice
  ([GCP-13](../../decisions/gcp.md#gcp-13-crossplane-not-config-connector)).
- **Gateway, NetworkPolicy, alert policy, dashboard and uptime check
  objects**: catalog concerns, so that four clouds share one definition.
- **Any credential as an input, and any key as an output**: the module
  authenticates through the provider's ambient credentials. The cluster CA is
  the one sensitive output; `helm_kubernetes` carries an exec block for
  `gke-gcloud-auth-plugin`, not a token.

## Reference

::include{file="opentofu/gcp/README.md" section="tf-docs"}
