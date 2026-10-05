---
title: Foundations
description: 'The Scaleway foundations module: what is decided for you, what is left out on purpose, and its full reference.'
sidebar:
  order: 2
---

[`opentofu/scaleway`](../../../opentofu/scaleway/README.md) builds an empty Kapsule cluster and steps away. Each default below is a decision, linked.

## What is decided for you

| What | How the module holds it | Decision |
| --- | --- | --- |
| Kapsule; Kosmos refused | validation on `control_plane_type` | [SCALEWAY-01](../../decisions/scaleway.md#scaleway-01-kapsule-not-kosmos) |
| Dedicated 4 control plane in `prod`, mutualized elsewhere | derived from `environment`; a `prod` cluster on the mutualized tier fails the plan | [SCALEWAY-02](../../decisions/scaleway.md#scaleway-02-a-dedicated-control-plane-in-production-mutualized-elsewhere) |
| Kapsule's Cilium, no CNI option | `cni = "cilium"`, no variable | [SCALEWAY-03](../../decisions/scaleway.md#scaleway-03-kapsules-own-cilium) |
| One pool per zone, `fr-par-1` and `fr-par-2`, `COMPUTE3-X8C-16G`, 2 to 5 nodes each | defaults; BASIC, DEV1, PLAY2, STARDUST and zones without the chosen generation refused | [SCALEWAY-04](../../decisions/scaleway.md#scaleway-04-compute3-x-pools-in-two-zones-under-the-cluster-autoscaler) |
| `least_waste` expander, a `max_availability` placement group per zone | default; `price` refused | [SCALEWAY-04](../../decisions/scaleway.md#scaleway-04-compute3-x-pools-in-two-zones-under-the-cluster-autoscaler) |
| An explicit Kubernetes version, patch auto-upgrade in a window | `kubernetes_version` and `maintenance_window` required | [SCALEWAY-05](../../decisions/scaleway.md#scaleway-05-an-explicit-version-patches-in-a-required-window) |
| No public IP on any node; one Public Gateway per zone | enforced | [SCALEWAY-06](../../decisions/scaleway.md#scaleway-06-full-isolation-behind-one-public-gateway-per-zone) |
| API server allow-list | `cluster_endpoint_public_access_cidrs` required, `0.0.0.0/0` refused | [SCALEWAY-06](../../decisions/scaleway.md#scaleway-06-full-isolation-behind-one-public-gateway-per-zone) |
| A /22 Private Network, a security group per cluster and zone | default; any other prefix length refused | [SCALEWAY-06](../../decisions/scaleway.md#scaleway-06-full-isolation-behind-one-public-gateway-per-zone) |
| One Project per environment | `project_id` required | [SCALEWAY-08](../../decisions/scaleway.md#scaleway-08-one-project-per-environment-one-scoped-crossplane-key) |
| One Crossplane key, Project-scoped, bound to the gateways' addresses | `crossplane_permission_sets` required, `AllProductsFullAccess` refused | [SCALEWAY-08](../../decisions/scaleway.md#scaleway-08-one-project-per-environment-one-scoped-crossplane-key) |
| Nothing written to Cockpit; a query-only token | `cockpit_token_enabled = true` | [SCALEWAY-11](../../decisions/scaleway.md#scaleway-11-workload-metrics-stay-in-the-cluster-never-pushed-to-cockpit), [SCALEWAY-12](../../decisions/scaleway.md#scaleway-12-a-query-only-cockpit-token) |

Every resource that takes tags carries `owner=`, `environment=`, `socle-version=` and `cluster=`, plus `additional_tags`, which cannot override those four.

`delete_additional_resources = false` by default: deleting the cluster leaves the Load Balancers and Block volumes Kubernetes created, so client data survives a teardown, and someone has to remove what is billed.

`oidc_issuer_url` and `workload_identity_pool` are outputs that are always null. Kapsule has no OIDC issuer and Scaleway no workload identity federation; the outputs exist so the four foundations modules share one output surface.

## What is deliberately absent

An option in the interface is one that is supported and tested, so these are refusals:

- **Kosmos.** A different CNI, no Private Network, no migration path.
- **A CNI variable.** `none` is not supported by Kapsule, so a self-managed Cilium is impossible, and Calico is worse on every count.
- **Controlled isolation.** Dev and staging would exercise a different egress path from production.
- **`price` as an autoscaler expander.** Upstream implements it for GCE and AWS only; on Scaleway it is a silent no-op.
- **Shared-vCPU and development node types.** A 99% SLO or less.
- **`feature_gates`, `admission_plugins`, `apiserver_cert_sans`, `open_id_connect_config`.** Kapsule exposes them; the socle needs none.
- **A Public Gateway bastion.** `bastion_enabled = false`: an inbound surface on the egress path that the allow-list does not cover.
- **Cockpit alerting, contacts, dashboards and data exports.** Catalog concerns, so four clouds share one definition ([SCALEWAY-13](../../decisions/scaleway.md#scaleway-13-scaleways-own-signals-federated-costed-per-project)).
- **Load Balancers, DNS records, certificates.** The cloud controller manager and the catalog own those, in the cluster ([SCALEWAY-07](../../decisions/scaleway.md#scaleway-07-add-ons-and-load-balancers-delegated-load-balancer-certificates-refused)).
- **A backend block and a state bucket.** State lives in the client's own account ([prerequisites](prerequisites.md#state)).

## Measured

As read on 2026-09-14, from `GET /instance/v1/zones/{zone}/products/servers`: the Zen 5 ranges (COMPUTE3, STANDARD3, BASIC3) exist in `fr-par-1`, `fr-par-2`, `nl-ams-1` and `nl-ams-2`; POP2 and PRO2 in `fr-par-3`, `nl-ams-2`, `nl-ams-3` and the three `pl-waw` zones. Scaleway's documentation disagrees; the module's validations encode the API.

As read on 2026-10-05 from the same API, in `fr-par-1`: `COMPUTE3-X8C-16G`, 8 vCPU and 16 GiB, €0.2341 an hour; `POP2-HC-8C-16G`, the same shape a generation older, €0.2128 an hour.

## Reference

::include{file="opentofu/scaleway/README.md" section="tf-docs"}
