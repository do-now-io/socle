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
| No Google service account: every workload, Crossplane included, a federated principal named by the project number ([GCP-14](../../decisions/gcp.md#gcp-14-workload-identity-federation-direct-principals-no-google-service-account)) | enforced |
| Crossplane's identity off unless asked; when on, it grants only `allowed_roles`, buckets under `<cluster_name>-` only and never deleted, nothing of Cloud DNS ([GCP-15](../../decisions/gcp.md#gcp-15-crossplanes-grants-bounded-by-the-roles-the-client-allows)) | opt-in |
| Gateway TLS at the load balancer: a Certificate Manager map for the public Gateway, a regional certificate for the private one, DNS-authorised ([GCP-16](../../decisions/gcp.md#gcp-16-gateway-tls-at-the-load-balancer-with-google-managed-certificates)) | opt-in |

<details>
<summary>Under the hood</summary>

- Private nodes flip Autopilot's default; the IP endpoints are off.
- Minimum sizes: Pods `/17`, proxy-only `/26`.
- Crossplane's principal is `crossplane-system/provider-gcp`, granted
  before the cluster has a node. `allowed_roles` takes at most nine roles;
  owner, editor, viewer, `iam.*`, `resourcemanager.*` and predefined admin or
  owner roles are refused at plan. The DNS records role, created here, is
  what Crossplane grants external-dns on the project: a zone's own IAM is
  never honoured.
- `project_number` is read from the API unless you pass it; it names every
  principal.
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

On a GKE Autopilot sandbox project, 2026-10-07 (PR #84), through
[`opentofu/clusters/gcp`](../../../opentofu/clusters/gcp/README.md):

- Under Crossplane's Project IAM Admin condition, granting an allowed role
  succeeded and granting `roles/owner` was denied; under the bucket
  condition, a bucket inside the prefix was created and one outside denied,
  `roles/storage.objectAdmin` on a bucket granted and `roles/storage.admin`
  denied.
- A managed zone's `getIamPolicy` and `setIamPolicy`, granted on the zone by
  a custom role and by `roles/dns.admin`, were never honoured (403 for
  minutes); record operations granted there were.
- Both certificates were issued once their authorization records resolved,
  and both shared Gateways programmed.
- A destroy takes two runs: GKE removes the Gateways' load balancers after
  the cluster, so the first fails on the certificate map, the regional
  certificate and the proxy-only subnetwork; the second completes, no
  Workload Identity binding left in the project policy.

CI also plans the module against floci-gcp, which implements no Compute
Engine API.

## Reference

::include{file="opentofu/gcp/README.md" section="tf-docs"}
