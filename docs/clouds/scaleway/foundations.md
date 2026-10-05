---
title: Foundations
description: 'The Scaleway foundations module: what is decided for you, what is deliberately absent, and its full reference.'
sidebar:
  order: 2
---

[`opentofu/scaleway`](../../../opentofu/scaleway/README.md) builds an empty
Kapsule cluster and steps away: the catalog arrives through the bootstrap and
Flux.

## What is decided for you

| Position | How | Decision |
| --- | --- | --- |
| Kapsule; Kosmos refused | validation | [SCALEWAY-01](../../decisions/scaleway.md#scaleway-01-kapsule-not-kosmos) |
| Dedicated 4 control plane in `prod`, mutualized elsewhere | from `environment`; `prod` on mutualized fails the plan | [SCALEWAY-02](../../decisions/scaleway.md#scaleway-02-a-dedicated-control-plane-in-production-mutualized-elsewhere) |
| Kapsule's Cilium | enforced | [SCALEWAY-03](../../decisions/scaleway.md#scaleway-03-kapsules-own-cilium) |
| One pool per zone, `fr-par-1` and `fr-par-2`, `COMPUTE3-X8C-16G`, 2 to 5 nodes | default; shared-vCPU and dev types refused | [SCALEWAY-04](../../decisions/scaleway.md#scaleway-04-compute3-x-pools-in-two-zones-under-the-cluster-autoscaler) |
| `least_waste` expander, a placement group per zone | default; `price` refused | [SCALEWAY-04](../../decisions/scaleway.md#scaleway-04-compute3-x-pools-in-two-zones-under-the-cluster-autoscaler) |
| An explicit version, patches in a window | both required | [SCALEWAY-05](../../decisions/scaleway.md#scaleway-05-an-explicit-version-patches-in-a-required-window) |
| No public IP on nodes; a Public Gateway per zone | enforced | [SCALEWAY-06](../../decisions/scaleway.md#scaleway-06-full-isolation-behind-one-public-gateway-per-zone) |
| API server allow-list, `0.0.0.0/0` refused | required | [SCALEWAY-06](../../decisions/scaleway.md#scaleway-06-full-isolation-behind-one-public-gateway-per-zone) |
| A /22 Private Network, a security group per cluster and zone | default | [SCALEWAY-06](../../decisions/scaleway.md#scaleway-06-full-isolation-behind-one-public-gateway-per-zone) |
| One Project per environment | `project_id` required | [SCALEWAY-08](../../decisions/scaleway.md#scaleway-08-one-project-per-environment-one-scoped-crossplane-key) |
| One Project-scoped Crossplane key, bound to the gateways' addresses | `crossplane_permission_sets` required, `AllProductsFullAccess` refused | [SCALEWAY-08](../../decisions/scaleway.md#scaleway-08-one-project-per-environment-one-scoped-crossplane-key) |
| Nothing written to Cockpit; a query-only token | default | [SCALEWAY-11](../../decisions/scaleway.md#scaleway-11-workload-metrics-stay-in-the-cluster-never-pushed-to-cockpit), [SCALEWAY-12](../../decisions/scaleway.md#scaleway-12-a-query-only-cockpit-token) |
| `owner`, `environment`, `socle-version`, `cluster` tags on every resource | enforced | — |

<details>
<summary>Under the hood</summary>

- Refused node types: BASIC, DEV1, PLAY2, STARDUST, and zones without the
  chosen generation. The placement groups are `max_availability`.
- `additional_tags` cannot override the four socle tags.
- `delete_additional_resources = false`: deleting the cluster leaves the Load
  Balancers and Block volumes Kubernetes created. Client data survives a
  teardown; someone has to remove what is billed.
- `oidc_issuer_url` and `workload_identity_pool` are always null: Kapsule has
  no OIDC issuer, Scaleway no workload identity federation. They keep one
  output surface across the four clouds.

</details>

## What is deliberately absent

- **Kosmos**: another CNI, no Private Network, no migration path.
- **A CNI variable**: Kapsule does not support `none`; Calico is worse on every count.
- **Controlled isolation**: dev and staging would use another egress path than production.
- **The `price` expander**: a silent no-op outside GCE and AWS.
- **Shared-vCPU and development node types**: a 99% SLO or less.
- **`feature_gates`, `admission_plugins`, `apiserver_cert_sans`, `open_id_connect_config`**: the socle needs none.
- **A Public Gateway bastion**: an inbound surface the allow-list does not cover.
- **Cockpit alerting, contacts, dashboards, exports**: catalog concerns ([SCALEWAY-13](../../decisions/scaleway.md#scaleway-13-scaleways-own-signals-federated-costed-per-project)).
- **Load Balancers, DNS records, certificates**: the cloud controller manager and the catalog own them ([SCALEWAY-07](../../decisions/scaleway.md#scaleway-07-add-ons-and-load-balancers-delegated-load-balancer-certificates-refused)).
- **A backend block and a state bucket**: yours ([prerequisites](prerequisites.md#state)).

## Measured

- **2026-09-14, instance API**: Zen 5 ranges (COMPUTE3, STANDARD3, BASIC3) exist in `fr-par-1`, `fr-par-2`, `nl-ams-1`, `nl-ams-2`; POP2 and PRO2 in `fr-par-3`, `nl-ams-2`, `nl-ams-3` and the three `pl-waw` zones. Scaleway's documentation disagrees; the validations follow the API.
- **2026-10-05, `fr-par-1`**: `COMPUTE3-X8C-16G` (8 vCPU, 16 GiB) €0.2341 an hour; `POP2-HC-8C-16G`, a generation older, €0.2128.

## Reference

::include{file="opentofu/scaleway/README.md" section="tf-docs"}
