---
title: Scaleway decisions
description: The decisions behind the Scaleway foundations, one per section, each with its status.
sidebar:
  order: 5
---

The decisions behind [`opentofu/scaleway`](../../opentofu/scaleway/README.md): the Kapsule cluster, its network, its identities and what the socle leaves to Scaleway. Two shape everything else. Scaleway has no workload identity federation, so the foundations mint one long-lived, scoped API key ([SCALEWAY-08](#scaleway-08-one-project-per-environment-one-scoped-crossplane-key)). The control plane cannot be made private, so its allowed-IP list is required ([SCALEWAY-06](#scaleway-06-full-isolation-behind-one-public-gateway-per-zone)).

## SCALEWAY-01: Kapsule, not Kosmos

**accepted** · 2026-09-14 · [`opentofu/scaleway/variables.tf`](../../opentofu/scaleway/variables.tf) (`control_plane_type`, lines 177-186)

**Context.** Scaleway sells two managed Kubernetes products. Kapsule runs its nodes as Scaleway Instances in one region, attached to a Private Network. Kosmos is the multi-cloud variant: it accepts external nodes, ships a different CNI, does not attach to a Private Network, and has no migration path to or from Kapsule. Kosmos control planes are billed even when mutualized (€0.1444 an hour in fr-par, against €0 for Kapsule mutualized, as read on 2026-10-05).

**Decision.** The module creates Kapsule clusters only. `control_plane_type` accepts `kapsule` and `kapsule-dedicated-4`, `-8` and `-16`; every Kosmos offer is refused by validation.

**Consequences.** One CNI, one network model and one product to test. A client who needs nodes outside Scaleway gets no answer from the socle on this cloud.

**Sources.** [Control plane offers](https://www.scaleway.com/en/docs/kubernetes/reference-content/kubernetes-control-plane-offers/) · [Kapsule pricing](https://www.scaleway.com/en/pricing/containers/), read 2026-09-14.

## SCALEWAY-02: A dedicated control plane in production, mutualized elsewhere

**accepted** · 2026-09-14 · [`opentofu/scaleway/main.tf`](../../opentofu/scaleway/main.tf) (lines 32-39) · [`opentofu/scaleway/cluster.tf`](../../opentofu/scaleway/cluster.tf) (lines 60-65)

**Context.** Kapsule offers a mutualized control plane and dedicated tiers, as read on 2026-09-14:

| | Mutualized | Dedicated 4 | Dedicated 8 |
| --- | --- | --- | --- |
| Price | free | €0.11 an hour | €0.18 an hour |
| SLA | none | 99.5% | 99.5% |
| Audit logs | no | yes | yes |
| API server | 1 replica | 2 | 2 |
| Max nodes / etcd | 150 / 55 MB | 250 / 200 MB | 500 / 200 MB |

A dedicated tier carries a 30-day commitment.

**Decision.** `control_plane_type` defaults to null, which derives the tier from `environment`: `kapsule-dedicated-4` in `prod`, `kapsule` elsewhere. A precondition refuses a `prod` cluster on the mutualized tier, whatever the override.

**Consequences.** Production gets the SLA, the audit log, two API server replicas and a 200 MB etcd, for €80.30 a month (730 hours). Dev and staging cost nothing for their control plane, and run on a 55 MB etcd that a CRD-heavy catalog fills faster: a sizing input, not a detail. The dedicated-control-plane quota caps an Organization at four production clusters ([limits](../clouds/scaleway/limits.md#provider-limits)).

**Sources.** [Control plane offers](https://www.scaleway.com/en/docs/kubernetes/reference-content/kubernetes-control-plane-offers/) · Scaleway product catalog API, `GET /product-catalog/v2alpha1/public-catalog/products?product_types=kubernetes`, read 2026-10-05.

## SCALEWAY-03: Kapsule's own Cilium

**accepted** · 2026-09-14 · [`opentofu/scaleway/cluster.tf`](../../opentofu/scaleway/cluster.tf) (lines 13-17) · [`opentofu/bootstrap/cilium.tf`](../../opentofu/bootstrap/cilium.tf) (lines 3-4)

**Context.** Kapsule operates the CNI as a system add-on, beside CoreDNS, kube-proxy and the CSI driver. It supports `cilium` and `calico`; `none` is not supported, so a self-managed Cilium cannot replace it. Scaleway's Cilium keeps kube-proxy, ships no Hubble, and its version is Scaleway's. `CiliumNodeConfig` is honoured: tunable, not replaceable. This is the Scaleway side of [SOCLE-02](socle.md#socle-02-cilium-and-coredns-before-flux-from-the-bootstrap).

**Decision.** The module sets `cni = "cilium"` and exposes no CNI variable. The bootstrap installs no Cilium and no CoreDNS on `cloud = "scaleway"`, and refuses its `cilium` variable there.

**Consequences.** The catalog treats Scaleway as the cloud where Cilium's own features are absent: no Hubble, no kube-proxy replacement, no Cilium Gateway API controller. Nothing implements Gateway API on Scaleway today ([limits](../clouds/scaleway/limits.md#what-the-socle-does-not-offer-here-yet)).

**Sources.** [Shared responsibility model](https://www.scaleway.com/en/docs/kubernetes/reference-content/kubernetes-shared-responsibility-model/) · [Cilium encryption on Kapsule](https://www.scaleway.com/en/docs/tutorials/enabling-encryption-in-kapsule-with-cilium/), read 2026-09-14.

## SCALEWAY-04: COMPUTE3-X pools in two zones, under the cluster-autoscaler

**accepted** · 2026-09-14 · [`opentofu/scaleway/cluster.tf`](../../opentofu/scaleway/cluster.tf) (lines 36-58, 85-136) · [`opentofu/scaleway/variables.tf`](../../opentofu/scaleway/variables.tf) (lines 103-122, 212-221, 249-299)

**Context.** There is no Karpenter for Scaleway and no spot market. The upstream cluster-autoscaler runs per pool; it removes an under-used node but never replaces a node with a cheaper one. A pool is single-zone and single-type. Scaleway's default expander is `random`. The `price` expander is implemented upstream for GCE and AWS only. The Instances API showed on 2026-09-14 that the current instance generation (COMPUTE3, STANDARD3, BASIC3) and the previous one (POP2, PRO2) never share a zone; Scaleway's documentation says otherwise. BASIC3-X has shared vCPU and a 99% SLO.

**Decision.** One pool per zone, each in its own `max_availability` placement group, over `availability_zones = ["fr-par-1", "fr-par-2"]`. Nodes are `COMPUTE3-X8C-16G`, 2 to 5 per pool, autoscaled and autohealed, on a 100 GB root volume. The autoscaler uses `least_waste` with `balance_similar_node_groups` and ignores DaemonSets in utilisation. Validation refuses the `price` expander, the shared-vCPU and development ranges, and a zone where the chosen generation does not exist.

**Consequences.** Every cluster runs at least 4 nodes and 2 zones, in every environment. Pool shape is a design act: each `pool_min_size` node is billed whether or not anything schedules on it. A homogeneous three-zone cluster exists only in pl-waw, on POP2 or PRO2.

**Sources.** [Multi-AZ clusters](https://www.scaleway.com/en/docs/kubernetes/reference-content/multi-az-clusters/) · [cluster-autoscaler options](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/resources/k8s_cluster) · `GET /instance/v1/zones/{zone}/products/servers`, read 2026-09-14.

## SCALEWAY-05: An explicit version, patches in a required window

**accepted** · 2026-09-14 · [`opentofu/scaleway/cluster.tf`](../../opentofu/scaleway/cluster.tf) (lines 11, 22-34) · [`opentofu/scaleway/variables.tf`](../../opentofu/scaleway/variables.tf) (lines 167-204)

**Context.** Kapsule has no release channel. A minor is supported for 14 months, with no paid extension; at end of support Scaleway upgrades the cluster within 30 days. Auto-upgrade moves patches inside the current minor, never the minor.

**Decision.** `kubernetes_version` is required, with no default. Patch auto-upgrade is on, inside `maintenance_window`, which is required too: a day and a UTC hour. `upgrade_pools = true` moves the pools with the control plane.

**Consequences.** Moving a minor is a change to `kubernetes_version`, applied by the pipeline, at least twice a year. With no channel to stagger an estate, the order dev, staging, production is the pipeline's to enforce, through each environment's window and version ([SOCLE-05](socle.md#socle-05-the-kubernetes-version-moves-by-rings-n-1-then-n)).

**Sources.** [Version support policy](https://www.scaleway.com/en/docs/kubernetes/reference-content/version-support-policy/), read 2026-09-14.

## SCALEWAY-06: Full isolation behind one Public Gateway per zone

**accepted** · 2026-09-14 · [`opentofu/scaleway/network.tf`](../../opentofu/scaleway/network.tf) (lines 8-118) · [`opentofu/scaleway/cluster.tf`](../../opentofu/scaleway/cluster.tf) (lines 68-83, 126-131) · [`opentofu/scaleway/variables.tf`](../../opentofu/scaleway/variables.tf) (lines 92-101, 143-161)

**Context.** The Kapsule control plane always has a public endpoint, and every cluster is created with an ACL allowing `0.0.0.0/0`. Nodes can carry a public IP (controlled isolation) or none (full isolation, egress through a Public Gateway). The Public Gateway is zoned and has no HA; Scaleway's answer to a zone outage is several gateways on one Private Network. New clusters join a default security group shared by every cluster in the Project. Kapsule takes a /22 per cluster.

**Decision.**

- Full isolation in every environment: `public_ip_disabled = true` on every pool, no variable to turn it off.
- One Public Gateway (`VPC-GW-S` by default) per zone the pools span, each with a reserved flexible IP and an IPAM address, all advertising the default route.
- `cluster_endpoint_public_access_cidrs` is required and replaces the default ACL; `0.0.0.0/0` is refused.
- One security group per cluster and zone, inbound dropped.
- One /22 Private Network per cluster (`private_network_cidr`), in a VPC the module creates per cluster by default (`create_vpc`), or in an existing one (`vpc_id`).

**Consequences.** Dev and staging exercise the egress path production uses. The gateways' addresses (`gateway_egress_cidrs`) are the cluster's stable source, which is what lets an IAM condition bind a key to it ([SCALEWAY-08](#scaleway-08-one-project-per-environment-one-scoped-crossplane-key)). Detaching every gateway cuts the nodes from their control plane. A zone loss costs that zone's share of egress, not the cluster's. Routing is VPC-wide, so clusters that must not route to each other need separate VPCs.

**Sources.** [Private Network](https://www.scaleway.com/en/docs/kubernetes/reference-content/secure-cluster-with-private-network/) · [allowed IPs](https://www.scaleway.com/en/docs/kubernetes/how-to/manage-allowed-ips/) · [Public Gateway FAQ](https://www.scaleway.com/en/docs/public-gateways/faq/) · [VPC concepts](https://www.scaleway.com/en/docs/vpc/concepts/), read 2026-09-14.

## SCALEWAY-07: Add-ons and load balancers delegated, Load Balancer certificates refused

**accepted** · 2026-09-14 · [`opentofu/scaleway/cluster.tf`](../../opentofu/scaleway/cluster.tf) · [`opentofu/scaleway/variables.tf`](../../opentofu/scaleway/variables.tf)

**Context.** CoreDNS, kube-proxy, the CNI and the CSI driver are Scaleway's on Kapsule, with no version field and no opt-out. `scaleway-cloud-controller-manager` creates a Load Balancer for every Service of type `LoadBalancer`, with about 50 annotations (PROXY protocol, HTTP/3, access logs, private load balancers, health checks). The CCM can also terminate TLS against certificates held in the Scaleway API.

**Decision.** The module exposes no add-on toggle and creates no Load Balancer, Load Balancer certificate or DNS record. Load balancers are the CCM's. TLS terminates in the cluster, with the certificates the catalog manages, never on the Load Balancer.

**Consequences.** Nothing to pin, nothing to trigger on the data plane. One certificate store and one renewal path, as on the other clouds. GPU pools get Scaleway's NVIDIA operator; workloads need startup taints, since drivers land after the node registers.

**Sources.** [CCM Load Balancer annotations](https://github.com/scaleway/scaleway-cloud-controller-manager/blob/master/docs/loadbalancer-annotations.md) · [shared responsibility model](https://www.scaleway.com/en/docs/kubernetes/reference-content/kubernetes-shared-responsibility-model/) · [NVIDIA GPU operator](https://www.scaleway.com/en/docs/kubernetes/how-to/use-nvidia-gpu-operator/), read 2026-09-14.

## SCALEWAY-08: One Project per environment, one scoped Crossplane key

**accepted** · 2026-09-14 · [`opentofu/scaleway/iam.tf`](../../opentofu/scaleway/iam.tf) (lines 16-62) · [`opentofu/scaleway/variables.tf`](../../opentofu/scaleway/variables.tf) (lines 9-17, 316-351) · [`opentofu/scaleway/main.tf`](../../opentofu/scaleway/main.tf) (lines 46-52)

**Context.** Scaleway has no workload identity federation and Kapsule exposes no OIDC issuer: a Pod calling the Scaleway API carries an API key. Resource-level IAM conditions exist for IAM, Key Manager and Secret Manager only, so a policy cannot say "this cluster, not that one". Request-level conditions (source IP, user agent, time) work on every product. Consumption carries no tags, so the Project is also the only cost boundary.

**Decision.** `project_id` is required, and one environment is one Project. The module creates one IAM application for the in-cluster Crossplane provider, a policy scoped to that Project granting `crossplane_permission_sets` (required, `AllProductsFullAccess` refused), bound by a `request.ip` condition to `crossplane_allowed_cidrs`, or to the gateways' egress addresses when empty, and an API key with an optional `crossplane_key_expires_at`. The key is returned as `crossplane_access_key` and the sensitive `crossplane_secret_key`.

**Consequences.** This is the one foundations module that issues a credential. A leaked key is useless outside the gateways' addresses, and expires if an expiry is set; rotating it replaces the key, and nothing in the socle picks up the new one yet. It also departs from [SOCLE-04](socle.md#socle-04-each-module-owns-its-cloud-access-the-foundations-never-change): on Scaleway the foundations create one Crossplane identity whose permission sets the client chooses, rather than each catalog module declaring its own access; adding a module that needs a new product means changing `crossplane_permission_sets`, an apply of the foundations. The catalog has no Scaleway Crossplane provider yet, so nothing in the cluster consumes this key today ([SCALEWAY-14](#scaleway-14-crossplane-through-scaleways-own-provider-pinned-with-a-regenerable-fork)).

**Sources.** [IAM policy conditions](https://www.scaleway.com/en/docs/iam/reference-content/understanding-policy-conditions/) · [products supporting resource-level conditions](https://www.scaleway.com/en/docs/iam/reference-content/supported-products-resource-level/) · [IAM and RBAC](https://www.scaleway.com/en/docs/kubernetes/reference-content/set-iam-permissions-and-implement-rbac/), read 2026-09-14.

## SCALEWAY-09: DNS and certificates through External-DNS and the Scaleway webhook

**proposed** · 2026-09-14 · [`oci/catalog/external-dns/resourceset.yaml`](../../oci/catalog/external-dns/resourceset.yaml) (lines 292-303)

**Context.** External-DNS has a Scaleway provider, and Scaleway publishes `cert-manager-webhook-scaleway`, a DNS-01 solver. Both are current, and using them keeps one External-DNS and one cert-manager across four clouds. The External-DNS tutorial still calls Scaleway DNS beta; Scaleway's own DNS documentation does not.

**Decision.** DNS records come from the catalog's External-DNS with its Scaleway provider; certificates from cert-manager with the Scaleway webhook.

**Consequences.** The External-DNS half is built: on `cloud = "scaleway"` the module reads `SCW_ACCESS_KEY` and `SCW_SECRET_KEY` from a Secret `external-dns-scaleway` the client creates in the `external-dns` namespace. It has not run against a real zone. The catalog has no cert-manager module, so the certificate half is not built, and this decision stays proposed until it is.

**Sources.** [External-DNS Scaleway provider](https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/scaleway.md) · [cert-manager webhook](https://github.com/scaleway/cert-manager-webhook-scaleway), read 2026-09-14 · [External-DNS module](../catalog/external-dns.md).

## SCALEWAY-10: Backup with Velero into Object Storage

**proposed** · 2026-09-14 · [`opentofu/bootstrap/catalog.tf`](../../opentofu/bootstrap/catalog.tf) (`catalog_clouds`)

**Context.** Kapsule has no managed backup. It places no restriction on privileged Pods or writable `hostPath`, so Velero's node-agent runs and a file-level copy of volume data is possible. Scaleway Object Storage is S3-compatible and supports Object Lock.

**Decision.** Backups go to Object Storage through the catalog's Velero, as on the other clouds, with Object Lock on the backup bucket and never on the state bucket, where WORM would make a legitimate state rewrite impossible.

**Consequences.** Not built: `catalog_clouds` offers `velero` on `aws` only, and the bootstrap refuses `kube.velero` on Scaleway. Until it is, a Scaleway cluster has no backup from the socle.

**Sources.** [Object Storage concepts](https://www.scaleway.com/en/docs/object-storage/concepts/), read 2026-09-14 · [Velero module](../catalog/velero.md).

## SCALEWAY-11: Workload metrics stay in the cluster, never pushed to Cockpit

**accepted** · 2026-09-14 · [`opentofu/scaleway/observability.tf`](../../opentofu/scaleway/observability.tf) (lines 8-36)

**Context.** Cockpit is Scaleway's Grafana over Mimir and Loki. Scaleway's own data (control plane metrics and logs, node metrics, audit logs) lands there free, retained 31 days for metrics and 7 for logs. Custom data is billed: €0.15 per million samples as read on 2026-09-14, so the ~300 samples a second the catalog scrapes would cost about €118 a month per cluster.

**Decision.** Workload metrics, logs and traces stay in the socle's in-cluster stack ([SOCLE-03](socle.md#socle-03-one-in-cluster-monitoring-stack-on-every-cloud)). Nothing the module creates can write to Cockpit.

**Consequences.** One monitoring stack on four clouds, on nodes already paid for. Scaleway's own signals stay in Cockpit, reachable through the token of [SCALEWAY-12](#scaleway-12-a-query-only-cockpit-token).

**Sources.** [Cockpit pricing](https://www.scaleway.com/en/docs/cockpit/reference-content/cockpit-pricing/) · [Cockpit product integration](https://www.scaleway.com/en/docs/cockpit/reference-content/cockpit-product-integration/), read 2026-09-14.

## SCALEWAY-12: A query-only Cockpit token

**accepted** · 2026-09-14 · [`opentofu/scaleway/observability.tf`](../../opentofu/scaleway/observability.tf) (lines 15-36) · [`opentofu/scaleway/variables.tf`](../../opentofu/scaleway/variables.tf) (lines 357-361)

**Context.** Reading Scaleway's metrics and logs out of Cockpit needs a token. A token can carry query, write and rule-setup scopes; writing is what Cockpit bills.

**Decision.** With `cockpit_token_enabled` (default `true`), the module creates one Cockpit token in the Project that may query metrics, logs and traces and do nothing else: no write scope, no rules, no alerts. It is returned as the sensitive `cockpit_token_secret`.

**Consequences.** A reader outside the cluster can query Scaleway's data without being able to add to the bill. Nothing in the socle consumes the token yet ([SCALEWAY-13](#scaleway-13-scaleways-own-signals-federated-costed-per-project)).

**Sources.** [Cockpit concepts](https://www.scaleway.com/en/docs/cockpit/concepts/), read 2026-09-14.

## SCALEWAY-13: Scaleway's own signals, federated, costed per Project

**proposed** · 2026-09-14

**Context.** Two ways lead out of Cockpit: Prometheus `/federate` with `match[]` selectors and a query token, free during its beta and billable afterwards at a rate Scaleway does not publish; and data exports, configured per data source (so per region and per Project), pushing to Datadog or an OTLP endpoint only. Container Registry, Domains and DNS, IAM and Key Manager publish no metrics; Audit Trail is not in Cockpit. Scaleway's alert manager is regionalised, per data source, and Scaleway's Grafana does not support Grafana's own alert manager. The Billing API's consumption endpoint returns one line per resource, filterable by Organization or Project, monthly only, free. Cockpit exposes no quota metric.

**Decision.**

- Scaleway's service metrics are read through `/federate`, every 300 seconds, with `match[]` narrowed to the products in use, by the reader the socle's monitoring designates. Data exports are refused.
- Alerting stays in the socle's own stack; Scaleway's alert manager is refused. The one Scaleway-side alert kept is a billing alert on the Organization.
- Cost is read from the consumption endpoint, per Project, which one Project per environment makes per environment ([SCALEWAY-08](#scaleway-08-one-project-per-environment-one-scoped-crossplane-key)).
- Quotas are raised at onboarding, as a checklist item, since there is nothing to alert on.

**Consequences.** Only the query token is built ([SCALEWAY-12](#scaleway-12-a-query-only-cockpit-token)). No federation job, no billing reader, no IP-bound Cockpit access exists. `/federate` costs €0 as read on 2026-09-14 and has no published price after the beta: the line to re-read before relying on it. Per-namespace cost does not exist on Scaleway.

**Sources.** [Federate Scaleway metrics](https://www.scaleway.com/en/docs/cockpit/how-to/federate-scaleway-metrics/) · [data exports](https://www.scaleway.com/en/docs/cockpit/how-to/manage-data-exports/) · [alert manager](https://www.scaleway.com/en/docs/cockpit/how-to/enable-alert-manager/) · [Cockpit limits](https://www.scaleway.com/en/docs/cockpit/reference-content/cockpit-limitations/) · [Billing API](https://www.scaleway.com/en/developers/api/billing/) · [billing alerts](https://www.scaleway.com/en/docs/billing/how-to/use-billing-alerts/) · [Organization quotas](https://www.scaleway.com/en/docs/organizations-and-projects/additional-content/organization-quotas/), read 2026-09-14.

## SCALEWAY-14: Crossplane through Scaleway's own provider, pinned, with a regenerable fork

**proposed** · 2026-09-14 · [`oci/catalog/crossplane/resourceset.yaml`](../../oci/catalog/crossplane/resourceset.yaml) (lines 25-27)

**Context.** `scaleway/crossplane-provider-scaleway` is Scaleway's, generated with Upjet from their Terraform provider, and supports Crossplane v2 with namespaced managed resources. As read from the GitHub API on 2026-09-14:

| | |
| --- | --- |
| Managed resources | 144, against 157 resources in the Terraform provider |
| Latest release | v0.6.0, 2026-02-06 |
| Last functional commit | 2026-04-27, in no release; Dependabot only since |
| Open issues | 14, two at `priority:highest` since August 2024 (`PublicGatewayIP` not created, `RDB Instance matchLabels` not working) |
| Terraform provider | v2.82.0, 2026-09-01, released roughly monthly |

Every resource a plausible claim needs exists (`rdb`, `redis`, `mongodb`, `object`, `mnq`, `secrets`, `keymanager`, `block`, `iam`). `crossplane-contrib/provider-terraform` was at v1.2.0 (August 2026) and active; `flux-iac/tofu-controller` at v0.16.5 with 158 open issues.

**Decision.** The catalog installs `xpkg.upbound.io/scaleway/provider-scaleway` pinned at `v0.6.0`, never a floating tag. The socle keeps a fork it can regenerate against a newer Terraform provider, since the provider is generated, not written. A resource the provider lacks is patched with `provider-terraform` inside the Composition that needs it. tofu-controller is refused: a second reconciler and a second state model beside Flux.

**Consequences.** Not built: the crossplane module installs providers on `aws` only, and on Scaleway installs the core with no provider. Standing up the fork is an estimated 3 to 5 days, once; a refresh about half a day. The two `priority:highest` bugs touch resources the catalog would use and must be tested before anything relies on them.

**Sources.** [crossplane-provider-scaleway](https://github.com/scaleway/crossplane-provider-scaleway) · [issue #201](https://github.com/scaleway/crossplane-provider-scaleway/issues/201) · [Upjet](https://github.com/crossplane/upjet) · [Scaleway's Crossplane tutorial](https://www.scaleway.com/en/docs/tutorials/get-started-crossplane-kubernetes/) · [provider-terraform](https://github.com/crossplane-contrib/provider-terraform) · [tofu-controller](https://github.com/flux-iac/tofu-controller) · [terraform-provider-scaleway](https://github.com/scaleway/terraform-provider-scaleway), read 2026-09-14.
