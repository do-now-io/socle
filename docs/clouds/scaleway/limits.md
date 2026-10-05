---
title: Limits
description: What no apply can finish on Scaleway, the provider limits the socle runs into, and what it does not offer there yet.
sidebar:
  order: 3
---

## What no apply can finish

- **Quota**: 4 `COMPUTE3-X8C-16G` nodes per cluster, up to 10; a raise is a support ticket, opened before the first apply ([prerequisites](prerequisites.md#quotas)).
- **Identity validation**: without it most production instance types have no quota.
- **The `external-dns-scaleway` Secret**: with External-DNS on, you create it in `external-dns`, with `SCW_ACCESS_KEY` and `SCW_SECRET_KEY` of a key that may write the zone.

## Provider limits

As read on 2026-09-14 unless dated otherwise.

- **No workload identity, no OIDC issuer**: anything in the cluster that calls Scaleway holds a long-lived API key in a Secret.
- **The Project is the only IAM boundary** between two clusters.
- **The control plane is always public**: deleting the module's ACL restores Kapsule's `0.0.0.0/0` rule.
- **etcd is capped** at 55 MB mutualized, 200 MB dedicated (tiers below).
- **Four dedicated control planes per Organization** before a ticket.
- **No Hubble, no kube-proxy replacement**; Scaleway sets the Cilium, CoreDNS, kube-proxy and CSI versions.
- **No Karpenter, no spot, no consolidation**: the autoscaler only removes idle nodes.
- **Savings plans are the only discount**: compute only, 12 or 36 months, binding, rate unpublished.
- **Instance generations never share a zone**: fr-par and nl-ams give two zones of the current one.
- **The Public Gateway is zoned, no HA**: losing every gateway cuts the nodes from their control plane.
- **Kapsule's default security group is shared** per Project; the module gives each cluster its own.
- **No release channel**: 14 months of support per minor; Scaleway upgrades within 30 days of end of support.
- **Billing has no tags**: per Organization or Project, monthly, no per-namespace cost.
- **Quotas by ticket only**, none published for Zen 5, no quota metric.
- **No Cockpit signals** from Container Registry, Domains and DNS, IAM, Key Manager or Audit Trail; `/federate` free in beta only.
- **No TFLint ruleset, no emulator**: CI runs `tofu test` and a plan with fixture credentials; neither proves convergence.

<details>
<summary>Under the hood</summary>

Control plane tiers, fr-par, 2026-10-05:

| | Mutualized | Dedicated 4 | Dedicated 8 | Dedicated 16 |
| --- | --- | --- | --- | --- |
| Price | free | €0.11 an hour | €0.18 an hour | €0.35 an hour |
| SLA | none | 99.5% | 99.5% | not read |
| Audit logs | no | yes | yes | not read |
| API server replicas | 1 | 2 | 2 | not read |
| Max nodes / etcd | 150 / 55 MB | 250 / 200 MB | 500 / 200 MB | not read |

- Only pl-waw runs one generation (POP2, PRO2) in three zones.
- The `price` expander is a no-op outside GCE and AWS; the module refuses it.
- Savings plans are billed in full, used or not, neither cancellable nor
  exchangeable.
- Registry health is seen from Flux's side, as failed pulls.

</details>

## What the socle does not offer here yet

- **No Gateway API implementation**: CRDs only, no shared Gateway, no route; ArgoCD and Grafana are not exposed.
- **No Crossplane provider**: the foundations' Crossplane key has no consumer ([SCALEWAY-14](../../decisions/scaleway.md#scaleway-14-crossplane-through-scaleways-own-provider-pinned-with-a-regenerable-fork)).
- **No Velero**: AWS only ([SCALEWAY-10](../../decisions/scaleway.md#scaleway-10-backup-with-velero-into-object-storage)).
- **No cert-manager** ([SCALEWAY-09](../../decisions/scaleway.md#scaleway-09-dns-and-certificates-through-external-dns-and-the-scaleway-webhook)).
- **No Cockpit federation, no billing reader**: the query token only ([SCALEWAY-13](../../decisions/scaleway.md#scaleway-13-scaleways-own-signals-federated-costed-per-project)).
- **No `opentofu/clusters/scaleway` root** ([quickstart](../../getting-started/scaleway.md)).
- **No key rotation**: changing `crossplane_key_expires_at` replaces the key; nothing carries it into the cluster.
