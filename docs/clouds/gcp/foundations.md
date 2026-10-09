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

| Position | |
| --- | --- |
| Autopilot, no cluster mode option | enforced |
| Regular release channel; `EXTENDED` refused | default |
| A maintenance window of at least 4 hours, no default | required |
| Upgrade notifications to a Pub/Sub topic | default |
| Only the free system metrics; system and workload logs | default |
| Backup for GKE agent off | default |
| Workload Identity, pool and principal prefix as outputs | Autopilot |
| Dataplane V2 and NetworkPolicy | Autopilot |
| GKE's Gateway API controller, standard channel | default |
| Private nodes and Cloud NAT | default |
| DNS-based control plane endpoint only; no client certificate | default |
| Nodes `/22`, Pods `/16`, proxy-only `/23`, no Services range | default |
| Subnet flow logs, 0.5 sampling over 10 minutes | default |
| GKE cost allocation on from creation | default |
| `owner`, `environment`, `socle-version` labels on every billable resource | enforced |
| Deletion protection on | default |

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
- **Config Connector**: Crossplane is the choice.
- **Gateway, NetworkPolicy, alert, dashboard and uptime objects**: catalog concerns.
- **Any credential as input, any key as output**: the cluster CA is the one sensitive output; `helm_kubernetes` carries an exec block for `gke-gcloud-auth-plugin`, not a token.

## Measured

Nothing measured on a real GCP project: CI plans the module against
floci-gcp, which implements no Compute Engine API.

## Reference

::include{file="opentofu/gcp/README.md" section="tf-docs"}
