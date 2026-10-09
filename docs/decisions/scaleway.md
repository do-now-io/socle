---
title: Scaleway decisions
description: The decisions behind the Scaleway foundations, one per section, each with its status.
sidebar:
  order: 5
---

The decisions behind [`opentofu/scaleway`](../../opentofu/scaleway/README.md): the Kapsule cluster, its network, its identities and what the socle leaves to Scaleway. Two shape the rest: with no workload identity federation, the foundations mint one scoped API key ([SCALEWAY-08](#scaleway-08-one-project-per-environment-one-scoped-crossplane-key)); the control plane cannot be private, so its allowed-IP list is required ([SCALEWAY-06](#scaleway-06-full-isolation-behind-one-public-gateway-per-zone)). Sources were read on 2026-09-14 unless dated otherwise.

## SCALEWAY-01: Kapsule, not Kosmos

**accepted** · 2026-09-14 · [`opentofu/scaleway/variables.tf`](../../opentofu/scaleway/variables.tf) (`control_plane_type`, lines 177-186)

**Decision.** Kapsule clusters only: `control_plane_type` accepts `kapsule` and `kapsule-dedicated-4`, `-8` and `-16`; every Kosmos offer is refused by validation.

**Context.** Kosmos, the multi-cloud variant, ships a different CNI, does not attach to a Private Network, has no migration path to Kapsule, and bills even its mutualized control plane (€0.1444 an hour in fr-par against €0, read 2026-10-05).

**Consequences.** One CNI, one network model, one product to test. A client who needs nodes outside Scaleway gets no answer from the socle on this cloud.

**Sources.** [Control plane offers](https://www.scaleway.com/en/docs/kubernetes/reference-content/kubernetes-control-plane-offers/) · [Kapsule pricing](https://www.scaleway.com/en/pricing/containers/).

## SCALEWAY-02: A dedicated control plane in production, mutualized elsewhere

**accepted** · 2026-09-14 · [`opentofu/scaleway/main.tf`](../../opentofu/scaleway/main.tf) (lines 32-39) · [`opentofu/scaleway/cluster.tf`](../../opentofu/scaleway/cluster.tf) (lines 60-65)

**Decision.** `control_plane_type` defaults to null, which derives the tier: `kapsule-dedicated-4` in `prod`, `kapsule` elsewhere. A precondition refuses a `prod` cluster on the mutualized tier.

**Context.** The mutualized control plane is free but has no SLA, no audit log, one API server and a 55 MB etcd; Dedicated 4 gives a 99.5% SLA, audit logs, two replicas and 200 MB etcd, with a 30-day commitment.

**Consequences.** Production pays €80.30 a month (730 hours at €0.11, read 2026-09-14). Dev and staging run a 55 MB etcd that a CRD-heavy catalog fills faster: a sizing input. The quota caps an Organization at four production clusters ([limits](../clouds/scaleway/limits.md#provider-limits)).

**Sources.** [Control plane offers](https://www.scaleway.com/en/docs/kubernetes/reference-content/kubernetes-control-plane-offers/) · Scaleway product catalog API, `GET /product-catalog/v2alpha1/public-catalog/products?product_types=kubernetes`, read 2026-10-05.

## SCALEWAY-03: Kapsule's own Cilium

**accepted** · 2026-09-14 · [`opentofu/scaleway/cluster.tf`](../../opentofu/scaleway/cluster.tf) (lines 13-17) · [`opentofu/bootstrap/cilium.tf`](../../opentofu/bootstrap/cilium.tf) (lines 3-4)

**Decision.** The module sets `cni = "cilium"` with no CNI variable; the bootstrap installs no Cilium and no CoreDNS on `cloud = "scaleway"` and refuses its `cilium` variable there.

**Context.** Kapsule operates the CNI as a system add-on and does not support `none`, so a self-managed Cilium cannot replace it. Its Cilium keeps kube-proxy, ships no Hubble, and is versioned by Scaleway. The Scaleway side of [SOCLE-02](socle.md#socle-02-cilium-and-coredns-before-flux-from-the-bootstrap).

**Consequences.** No Hubble, no kube-proxy replacement, no Cilium Gateway API controller: nothing implements Gateway API on Scaleway today ([limits](../clouds/scaleway/limits.md#what-the-socle-does-not-offer-here-yet)).

**Sources.** [Shared responsibility model](https://www.scaleway.com/en/docs/kubernetes/reference-content/kubernetes-shared-responsibility-model/) · [Cilium encryption on Kapsule](https://www.scaleway.com/en/docs/tutorials/enabling-encryption-in-kapsule-with-cilium/).

## SCALEWAY-04: COMPUTE3-X pools in two zones, under the cluster-autoscaler

**accepted** · 2026-09-14 · [`opentofu/scaleway/cluster.tf`](../../opentofu/scaleway/cluster.tf) (lines 36-58, 85-136) · [`opentofu/scaleway/variables.tf`](../../opentofu/scaleway/variables.tf) (lines 103-122, 212-221, 249-299)

**Decision.** One pool per zone over `availability_zones = ["fr-par-1", "fr-par-2"]`, each in a `max_availability` placement group, `COMPUTE3-X8C-16G` nodes, 2 to 5 per pool, autoscaled with `least_waste` and `balance_similar_node_groups`. Validation refuses the `price` expander, the shared-vCPU and development ranges, and a zone lacking the chosen generation.

**Context.** No Karpenter and no spot market on Scaleway; the cluster-autoscaler runs per single-zone, single-type pool, and its `price` expander exists for GCE and AWS only. The Instances API showed that COMPUTE3/STANDARD3/BASIC3 and POP2/PRO2 never share a zone, contrary to the documentation.

**Consequences.** Every cluster runs at least 4 nodes in 2 zones, each `pool_min_size` node billed whether used or not. A homogeneous three-zone cluster exists only in pl-waw, on POP2 or PRO2.

**Sources.** [Multi-AZ clusters](https://www.scaleway.com/en/docs/kubernetes/reference-content/multi-az-clusters/) · [cluster-autoscaler options](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/resources/k8s_cluster) · `GET /instance/v1/zones/{zone}/products/servers`.

## SCALEWAY-05: An explicit version, patches in a required window

**accepted** · 2026-09-14 · [`opentofu/scaleway/cluster.tf`](../../opentofu/scaleway/cluster.tf) (lines 11, 22-34) · [`opentofu/scaleway/variables.tf`](../../opentofu/scaleway/variables.tf) (lines 167-204)

**Decision.** `kubernetes_version` and `maintenance_window` (a day and a UTC hour) are required. Patch auto-upgrade is on inside the window; `upgrade_pools = true`.

**Context.** Kapsule has no release channel. A minor is supported 14 months with no paid extension, then Scaleway upgrades within 30 days; auto-upgrade moves patches only.

**Consequences.** A minor moves by a change to `kubernetes_version`, at least twice a year; the dev, staging, production order is the pipeline's ([SOCLE-05](socle.md#socle-05-the-kubernetes-version-moves-by-rings-n-1-then-n)).

**Sources.** [Version support policy](https://www.scaleway.com/en/docs/kubernetes/reference-content/version-support-policy/).

## SCALEWAY-06: Full isolation behind one Public Gateway per zone

**accepted** · 2026-09-14 · [`opentofu/scaleway/network.tf`](../../opentofu/scaleway/network.tf) (lines 8-118) · [`opentofu/scaleway/cluster.tf`](../../opentofu/scaleway/cluster.tf) (lines 68-83, 126-131) · [`opentofu/scaleway/variables.tf`](../../opentofu/scaleway/variables.tf) (lines 92-101, 143-161)

**Decision.** Full isolation everywhere (`public_ip_disabled = true`, no opt-out); one Public Gateway (`VPC-GW-S`) per zone with a reserved IP, all advertising the default route; `cluster_endpoint_public_access_cidrs` required, `0.0.0.0/0` refused; one inbound-drop security group per cluster and zone; one /22 Private Network per cluster, in a per-cluster VPC (`create_vpc`) or an existing one (`vpc_id`).

**Context.** The control plane is always public, with a default ACL of `0.0.0.0/0`. The Public Gateway is zonal with no HA; Scaleway's answer is several gateways on one Private Network. New clusters share a Project-wide default security group.

**Consequences.** Dev and staging exercise production's egress path. `gateway_egress_cidrs` is the stable source an IAM condition binds a key to ([SCALEWAY-08](#scaleway-08-one-project-per-environment-one-scoped-crossplane-key)). Detaching every gateway cuts nodes from the control plane; routing is VPC-wide, so isolated clusters need separate VPCs.

**Sources.** [Private Network](https://www.scaleway.com/en/docs/kubernetes/reference-content/secure-cluster-with-private-network/) · [allowed IPs](https://www.scaleway.com/en/docs/kubernetes/how-to/manage-allowed-ips/) · [Public Gateway FAQ](https://www.scaleway.com/en/docs/public-gateways/faq/) · [VPC concepts](https://www.scaleway.com/en/docs/vpc/concepts/).

## SCALEWAY-07: Add-ons and load balancers delegated, Load Balancer certificates refused

**accepted** · 2026-09-14 · [`opentofu/scaleway/cluster.tf`](../../opentofu/scaleway/cluster.tf) · [`opentofu/scaleway/variables.tf`](../../opentofu/scaleway/variables.tf)

**Decision.** No add-on toggle, no Load Balancer, Load Balancer certificate or DNS record: load balancers are the CCM's, and TLS terminates in the cluster with the catalog's certificates.

**Context.** CoreDNS, kube-proxy, the CNI and the CSI driver are Scaleway's, with no version field or opt-out. The CCM creates a Load Balancer per `LoadBalancer` Service and can terminate TLS on certificates held in the Scaleway API.

**Consequences.** One certificate store and renewal path, as on the other clouds. GPU pools get Scaleway's NVIDIA operator; workloads need startup taints, since drivers land after the node registers.

**Sources.** [CCM Load Balancer annotations](https://github.com/scaleway/scaleway-cloud-controller-manager/blob/master/docs/loadbalancer-annotations.md) · [shared responsibility model](https://www.scaleway.com/en/docs/kubernetes/reference-content/kubernetes-shared-responsibility-model/) · [NVIDIA GPU operator](https://www.scaleway.com/en/docs/kubernetes/how-to/use-nvidia-gpu-operator/).

## SCALEWAY-08: One Project per environment, one scoped Crossplane key

**accepted** · 2026-09-14 · [`opentofu/scaleway/iam.tf`](../../opentofu/scaleway/iam.tf) (lines 16-62) · [`opentofu/scaleway/variables.tf`](../../opentofu/scaleway/variables.tf) (lines 9-17, 316-351) · [`opentofu/scaleway/main.tf`](../../opentofu/scaleway/main.tf) (lines 46-52)

**Decision.** `project_id` is required: one environment, one Project. The module creates one IAM application for Crossplane, a Project-scoped policy granting `crossplane_permission_sets` (`AllProductsFullAccess` refused) under a `request.ip` condition on `crossplane_allowed_cidrs` or the gateways' egress, and an API key with optional `crossplane_key_expires_at`, output as `crossplane_access_key` and sensitive `crossplane_secret_key`.

**Context.** No workload identity federation and no OIDC issuer on Kapsule. Resource-level IAM conditions exist only for IAM, Key Manager and Secret Manager; request-level ones (source IP) work everywhere. Consumption carries no tags, so the Project is the only cost boundary.

**Consequences.** The one foundations module that issues a credential: a leaked key is useless outside the gateways' addresses, and nothing picks up a rotated one yet. It departs from [SOCLE-04](socle.md#socle-04-each-module-owns-its-cloud-access-the-foundations-never-change): a module needing a new product means an apply of the foundations. Nothing consumes the key today ([SCALEWAY-14](#scaleway-14-crossplane-through-scaleways-own-provider-pinned-with-a-regenerable-fork)).

**Sources.** [IAM policy conditions](https://www.scaleway.com/en/docs/iam/reference-content/understanding-policy-conditions/) · [products supporting resource-level conditions](https://www.scaleway.com/en/docs/iam/reference-content/supported-products-resource-level/) · [IAM and RBAC](https://www.scaleway.com/en/docs/kubernetes/reference-content/set-iam-permissions-and-implement-rbac/).

## SCALEWAY-09: DNS and certificates through External-DNS and the Scaleway webhook

**proposed** · 2026-09-14 · [`oci/catalog/external-dns/resourceset.yaml`](../../oci/catalog/external-dns/resourceset.yaml) (lines 292-303)

**Decision.** DNS records from the catalog's External-DNS with its Scaleway provider; certificates from cert-manager with `cert-manager-webhook-scaleway`.

**Context.** Both are current and keep one External-DNS and one cert-manager across four clouds.

**Consequences.** External-DNS is built, reading `SCW_ACCESS_KEY` and `SCW_SECRET_KEY` from a client-created Secret `external-dns-scaleway` in `external-dns`, never run against a real zone. The catalog has no cert-manager module, so this stays proposed.

**Sources.** [External-DNS Scaleway provider](https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/scaleway.md) · [cert-manager webhook](https://github.com/scaleway/cert-manager-webhook-scaleway) · [External-DNS module](../catalog/external-dns.md).

## SCALEWAY-10: Backup with Velero into Object Storage

**proposed** · 2026-09-14 · [`opentofu/bootstrap/catalog.tf`](../../opentofu/bootstrap/catalog.tf) (`catalog_clouds`)

**Decision.** Backups go to Object Storage through the catalog's Velero, with Object Lock on the backup bucket and never on the state bucket, where WORM would block a legitimate state rewrite.

**Context.** Kapsule has no managed backup and allows privileged Pods and `hostPath`, so the node-agent runs; Object Storage is S3-compatible with Object Lock.

**Consequences.** Not built: `velero` is offered on `aws` only, so a Scaleway cluster has no backup from the socle.

**Sources.** [Object Storage concepts](https://www.scaleway.com/en/docs/object-storage/concepts/) · [Velero module](../catalog/velero.md).

## SCALEWAY-11: Workload metrics stay in the cluster, never pushed to Cockpit

**accepted** · 2026-09-14 · [`opentofu/scaleway/observability.tf`](../../opentofu/scaleway/observability.tf) (lines 8-36)

**Decision.** Workload metrics, logs and traces stay in the in-cluster stack ([SOCLE-03](socle.md#socle-03-one-in-cluster-monitoring-stack-on-every-cloud)); nothing the module creates can write to Cockpit.

**Context.** Scaleway's own data lands in Cockpit free; custom data costs €0.15 per million samples (read 2026-09-14), about €118 a month per cluster for the catalog's ~300 samples a second.

**Consequences.** One monitoring stack on four clouds, on nodes already paid for. Scaleway's signals stay in Cockpit, read through [SCALEWAY-12](#scaleway-12-a-query-only-cockpit-token).

**Sources.** [Cockpit pricing](https://www.scaleway.com/en/docs/cockpit/reference-content/cockpit-pricing/) · [Cockpit product integration](https://www.scaleway.com/en/docs/cockpit/reference-content/cockpit-product-integration/).

## SCALEWAY-12: A query-only Cockpit token

**accepted** · 2026-09-14 · [`opentofu/scaleway/observability.tf`](../../opentofu/scaleway/observability.tf) (lines 15-36) · [`opentofu/scaleway/variables.tf`](../../opentofu/scaleway/variables.tf) (lines 357-361)

**Decision.** With `cockpit_token_enabled` (default `true`), one Cockpit token that may query metrics, logs and traces and nothing else, output as sensitive `cockpit_token_secret`.

**Context.** Reading Cockpit needs a token; a token can also write, which is what Cockpit bills.

**Consequences.** A reader can query Scaleway's data without adding to the bill. Nothing in the socle consumes it yet ([SCALEWAY-13](#scaleway-13-scaleways-own-signals-federated-costed-per-project)).

**Sources.** [Cockpit concepts](https://www.scaleway.com/en/docs/cockpit/concepts/).

## SCALEWAY-13: Scaleway's own signals, federated, costed per Project

**proposed** · 2026-09-14

**Decision.** Service metrics through `/federate` every 300 s, `match[]` narrowed to products in use; data exports refused. Alerting stays in the socle's stack, except one billing alert on the Organization. Cost from the Billing API's consumption endpoint, per Project. Quotas raised at onboarding.

**Context.** `/federate` is free during its beta, unpriced after; data exports push only to Datadog or OTLP, per data source. Scaleway's alert manager is regionalised. The consumption endpoint is monthly and free; Cockpit exposes no quota metric.

**Consequences.** Only the query token is built ([SCALEWAY-12](#scaleway-12-a-query-only-cockpit-token)). `/federate`'s post-beta price is the line to re-read before relying on it. Per-namespace cost does not exist on Scaleway.

**Sources.** [Federate Scaleway metrics](https://www.scaleway.com/en/docs/cockpit/how-to/federate-scaleway-metrics/) · [data exports](https://www.scaleway.com/en/docs/cockpit/how-to/manage-data-exports/) · [alert manager](https://www.scaleway.com/en/docs/cockpit/how-to/enable-alert-manager/) · [Cockpit limits](https://www.scaleway.com/en/docs/cockpit/reference-content/cockpit-limitations/) · [Billing API](https://www.scaleway.com/en/developers/api/billing/) · [billing alerts](https://www.scaleway.com/en/docs/billing/how-to/use-billing-alerts/) · [Organization quotas](https://www.scaleway.com/en/docs/organizations-and-projects/additional-content/organization-quotas/).

## SCALEWAY-14: Crossplane through Scaleway's own provider, pinned, with a regenerable fork

**proposed** · 2026-09-14 · [`oci/catalog/crossplane/resourceset.yaml`](../../oci/catalog/crossplane/resourceset.yaml) (lines 25-27)

**Decision.** Install `xpkg.upbound.io/scaleway/provider-scaleway` pinned at `v0.6.0`, and keep a fork the socle can regenerate against a newer Terraform provider. A missing resource is patched with `provider-terraform` inside its Composition; tofu-controller is refused, a second reconciler beside Flux.

**Context.** The provider is Scaleway's, Upjet-generated, Crossplane v2-ready, with 144 managed resources covering every plausible claim; its last release is v0.6.0 (2026-02-06), with Dependabot-only commits since April 2026 and two `priority:highest` bugs open since August 2024.

**Consequences.** Not built: crossplane installs providers on `aws` only. The fork is an estimated 3 to 5 days once, half a day per refresh. The two bugs touch resources the catalog would use and must be tested first.

**Sources.** [crossplane-provider-scaleway](https://github.com/scaleway/crossplane-provider-scaleway) · [issue #201](https://github.com/scaleway/crossplane-provider-scaleway/issues/201) · [Upjet](https://github.com/crossplane/upjet) · [Scaleway's Crossplane tutorial](https://www.scaleway.com/en/docs/tutorials/get-started-crossplane-kubernetes/) · [provider-terraform](https://github.com/crossplane-contrib/provider-terraform) · [tofu-controller](https://github.com/flux-iac/tofu-controller) · [terraform-provider-scaleway](https://github.com/scaleway/terraform-provider-scaleway).
