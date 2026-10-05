---
title: Limits
description: What no apply can finish on Scaleway, the provider limits the socle runs into, and what it does not offer there yet.
sidebar:
  order: 3
---

## What no apply can finish

- **Quota.** The defaults need 4 `COMPUTE3-X8C-16G` nodes per cluster, up to 10; the quota table publishes no figure for that generation, and `POP2-HC-8C-16G` defaults to 2. Raising a quota is a support ticket, opened before the first apply ([prerequisites](prerequisites.md#quotas)).
- **Identity validation.** Without it most production instance types have no quota at all.
- **The `external-dns-scaleway` Secret.** With External-DNS on, the client creates it in the `external-dns` namespace, holding `SCW_ACCESS_KEY` and `SCW_SECRET_KEY` of a key that may write the zone. A credential never enters OpenTofu.

## Provider limits

As read on 2026-09-14 unless dated otherwise.

**Identity.**

- No workload identity federation and no OIDC issuer: `oidc_issuer_url` and `workload_identity_pool` are null. Anything in the cluster that calls the Scaleway API holds a long-lived API key in a Secret.
- Per-resource IAM conditions exist for IAM, Key Manager and Secret Manager only. The Project is the only boundary between two clusters.

**Control plane.**

- Always public. Kapsule creates each cluster with an ACL allowing `0.0.0.0/0`; the module replaces it and refuses that value, and deleting the module's ACL puts the open rule back.
- etcd is capped at 55 MB on the mutualized tier and 200 MB on the dedicated tiers.

| | Mutualized | Dedicated 4 | Dedicated 8 | Dedicated 16 |
| --- | --- | --- | --- | --- |
| Price, fr-par, 2026-10-05 | free | €0.11 an hour | €0.18 an hour | €0.35 an hour |
| SLA | none | 99.5% | 99.5% | not read |
| Audit logs | no | yes | yes | not read |
| API server replicas | 1 | 2 | 2 | not read |
| Max nodes / etcd | 150 / 55 MB | 250 / 200 MB | 500 / 200 MB | not read |

- The dedicated-control-plane quota (4 by default) caps an Organization at four production clusters before a ticket.

**CNI.**

- Kapsule's Cilium ships no Hubble and no kube-proxy replacement; kube-proxy stays.
- The CNI version is Scaleway's and cannot be pinned. So are CoreDNS, kube-proxy and the CSI driver.

**Capacity.**

- No Karpenter, no spot market, no consolidation: the cluster-autoscaler removes an idle node but never swaps a node for a cheaper one.
- Savings plans are the only discount: compute only, 12 or 36 months, billed in full used or not, neither cancellable nor exchangeable, rate unpublished.
- The `price` expander is a no-op outside GCE and AWS; the module refuses it.

**Zones.**

- The current and previous instance generations never share a zone. Only pl-waw runs one generation (POP2, PRO2) in three zones; fr-par and nl-ams give two zones of the current one.
- The Public Gateway is zoned and has no HA. The module puts one in each zone; losing every gateway cuts the nodes from their control plane.
- The Kapsule default security group is shared by every cluster in the Project. The module gives each cluster its own.

**Versions.**

- No release channel. 14 months of support per minor, no paid extension; Scaleway upgrades a cluster within 30 days of end of support.

**Cost.**

- Consumption carries no tags. Billing is read per Organization or Project, monthly, with no daily breakdown and no per-namespace cost.

**Quotas.**

- Raised by support ticket only. Identity validation comes first. No published quota for the Zen 5 ranges. No quota metric in Cockpit.

**Observability.**

- Container Registry, Domains and DNS, IAM and Key Manager publish no metrics and no logs to Cockpit; Audit Trail is not in Cockpit. Registry health is seen from Flux's side, as failed pulls.
- `/federate` is free during its beta and has no published price afterwards.

**Tooling.**

- No TFLint ruleset for Scaleway exists; `.tflint.hcl` carries the `terraform` preset alone.
- No emulator, from floci or anyone. CI runs `tofu test` on the module and a `tofu plan` of `examples/minimal`, with fixture credentials; neither proves convergence.

## What the socle does not offer here yet

- **No Gateway API implementation.** The `gateway_api` module installs the CRDs only. The bootstrap's GatewayClass is empty on Scaleway, so no shared Gateway exists and no catalog module renders a route: the socle exposes neither ArgoCD nor Grafana outside the cluster.
- **No Crossplane provider for Scaleway.** The crossplane module installs the core and no provider, so the foundations' Crossplane key has no consumer ([SCALEWAY-14](../../decisions/scaleway.md#scaleway-14-crossplane-through-scaleways-own-provider-pinned-with-a-regenerable-fork)).
- **No Velero.** The catalog offers it on AWS only ([SCALEWAY-10](../../decisions/scaleway.md#scaleway-10-backup-with-velero-into-object-storage)).
- **No cert-manager.** External-DNS has its Scaleway branch; certificates have no module ([SCALEWAY-09](../../decisions/scaleway.md#scaleway-09-dns-and-certificates-through-external-dns-and-the-scaleway-webhook)).
- **No federation of Cockpit, no billing reader.** Only the query token exists ([SCALEWAY-13](../../decisions/scaleway.md#scaleway-13-scaleways-own-signals-federated-costed-per-project)).
- **No `opentofu/clusters/scaleway` root.** The client composes the foundations and the bootstrap ([quickstart](../../getting-started/scaleway.md)).
- **No key rotation.** Changing `crossplane_key_expires_at` replaces the Crossplane key; nothing carries the new one into the cluster.
