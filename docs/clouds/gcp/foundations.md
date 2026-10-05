---
title: Foundations
description: 'The GCP foundations module: what is decided for you, what is deliberately absent, and its full reference.'
sidebar:
  order: 2
---

[`opentofu/gcp`](../../../opentofu/gcp/README.md) builds the network and an
empty Autopilot cluster, then steps away: the catalog arrives through the
bootstrap and Flux.

## What is decided for you

*Enforced*: no variable. *Default*: a variable changes it.

| Position | | Decision |
| --- | --- | --- |
| Autopilot, no cluster mode option | enforced | [GCP-01](../../decisions/gcp.md#gcp-01-autopilot-only-no-cluster-mode-option) |
| Regular release channel; `EXTENDED` refused | default | [GCP-02](../../decisions/gcp.md#gcp-02-regular-release-channel-rings-ordered-by-the-maintenance-window) |
| A maintenance window of at least 4 hours, no default | required | [GCP-02](../../decisions/gcp.md#gcp-02-regular-release-channel-rings-ordered-by-the-maintenance-window) |
| Upgrade notifications to a Pub/Sub topic | default | [GCP-02](../../decisions/gcp.md#gcp-02-regular-release-channel-rings-ordered-by-the-maintenance-window) |
| Only the free system metrics; system and workload logs | default | [GCP-03](../../decisions/gcp.md#gcp-03-only-the-free-system-metrics-auto-monitoring-refused) |
| Backup for GKE agent off | default | [GCP-05](../../decisions/gcp.md#gcp-05-velero-by-default-backup-for-gke-as-a-priced-option) |
| Workload Identity, pool and principal prefix as outputs | Autopilot | [GCP-06](../../decisions/gcp.md#gcp-06-workload-identity-federation-a-google-service-account-per-kubernetes-service-account) |
| Dataplane V2 and NetworkPolicy | Autopilot | [GCP-07](../../decisions/gcp.md#gcp-07-dataplane-v2-and-plain-networkpolicy) |
| GKE's Gateway API controller, standard channel | default | [GCP-08](../../decisions/gcp.md#gcp-08-exposure-through-gkes-gateway-controller) |
| Private nodes and Cloud NAT | default | [GCP-09](../../decisions/gcp.md#gcp-09-private-nodes-a-dns-endpoint-and-a-sized-reference-network) |
| DNS-based control plane endpoint only; no client certificate | default | [GCP-09](../../decisions/gcp.md#gcp-09-private-nodes-a-dns-endpoint-and-a-sized-reference-network) |
| Nodes `/22`, Pods `/16`, proxy-only `/23`, no Services range | default | [GCP-09](../../decisions/gcp.md#gcp-09-private-nodes-a-dns-endpoint-and-a-sized-reference-network) |
| Subnet flow logs, 0.5 sampling over 10 minutes | default | [GCP-10](../../decisions/gcp.md#gcp-10-subnet-flow-logs-on-at-half-sampling-over-ten-minutes) |
| GKE cost allocation on from creation | default | [GCP-12](../../decisions/gcp.md#gcp-12-cost-attribution-through-the-detailed-billing-export) |
| `owner`, `environment`, `socle-version` labels on every billable resource | enforced | — |
| Deletion protection on | default | — |

<details>
<summary>Under the hood</summary>

- Private nodes flip Autopilot's default; the IP endpoints are off.
- Minimum sizes: Pods `/17`, proxy-only `/26`.
- The network is the module's (`create_network = true`) or yours
  (`network_name`). In a Shared VPC whose subnets the network team owns, set
  `create_subnetwork = false` with `subnetwork_name` and `pod_range_name`,
  and the plan stops asking for NAT.

</details>

## What is deliberately absent

- **`EXTENDED` channel**: forbidden on Autopilot.
- **Workload Identity, CNI, datapath and Hubble toggles**: Autopilot enforces them.
- **`master_authorized_networks`, `master_ipv4_cidr_block`**: they govern the IP endpoints, which are off.
- **A Services range**: GKE assigns its own on Autopilot 1.27 and later.
- **Auto IPAM**: Preview when decided.
- **Auto-Monitoring, `gke_auto_upgrade_config`**: silent recurring cost.
- **Config Connector**: Crossplane is the choice ([GCP-13](../../decisions/gcp.md#gcp-13-crossplane-not-config-connector)).
- **Gateway, NetworkPolicy, alert, dashboard and uptime objects**: catalog concerns.
- **Any credential as input, any key as output**: the cluster CA is the one sensitive output; `helm_kubernetes` carries an exec block for `gke-gcloud-auth-plugin`, not a token.

## Measured

Nothing measured on a real GCP project: CI plans the module against
floci-gcp, which implements no Compute Engine API.

## Reference

::include{file="opentofu/gcp/README.md" section="tf-docs"}
