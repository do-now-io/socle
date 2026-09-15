# Kapsule: capabilities and limits against the hyperscalers

Socle targets four clouds. This document establishes what Kapsule actually
does, measured against EKS, GKE and AKS, and names the constraints the
Scaleway foundations module has to absorb.

**Kapsule is a viable foundation for the socle. Four of its limits are
structural — the module is shaped around them, not against them.**

## The four structural limits

| Limit | Consequence for the module |
| --- | --- |
| No workload identity federation | Pods authenticate to Scaleway with a long-lived API key, held as a Secret |
| The control plane always has a public IP | There is no fully private cluster; an IP allow-list is the only boundary |
| etcd capped at 55 MB (mutualized) / 200 MB (dedicated) | A CRD-heavy socle — Flux, Crossplane, the catalog — is a sizing input, not a detail |
| No spot market, no Karpenter | Capacity is fixed node types under cluster-autoscaler; the only discount is a three-year commitment |

None of these has a workaround inside the cluster. They are priced and
designed for, or the cluster is not run on Scaleway.

## What Kapsule gives that the hyperscalers do not

- **A free control plane.** Mutualized costs nothing. EKS, GKE and AKS all
  charge ~$0.10/hour per cluster. The catch is in the next section.
- **Cilium as the default, operated by Scaleway.** Socle standardizes on
  Cilium everywhere; on Kapsule it is the default CNI rather than something
  to install — with real caveats, see [CNI](#cni-cilium-but-not-ours).
- **API server knobs.** `feature_gates`, `admission_plugins`,
  `apiserver_cert_sans` and an OpenID Connect config are exposed as cluster
  fields. GKE Autopilot exposes none of them.
- **An EU-only footprint.** Three regions — `fr-par`, `nl-ams`, `pl-waw` —
  and a French operator. For clients who buy sovereignty, that is the
  product.

## Control plane offers

| | Mutualized | Dedicated 4 | Dedicated 8 | Dedicated 16 |
| --- | --- | --- | --- | --- |
| Price | **free** | €80.30/mo | €131.40/mo | €255.50/mo |
| SLA | **none** | 99.5% | 99.5% | 99.5% |
| Audit logs | **no** | yes | yes | yes |
| API server | 1 replica | 2, HA | 2, HA | 2, HA |
| Max nodes | 150 | 250 | 500 | 500 |
| Max etcd | 55 MB | 200 MB | 200 MB | 200 MB |
| Commitment | none | 30 days | 30 days | 30 days |

- etcd is replicated across three AZs in every offer. Only the dedicated
  offers put the API server itself in more than one zone — a *regional
  cluster* requires an HA dedicated control plane.
- The 30-day commitment is real: upgrading a tier restarts it, and
  downgrading during it is refused.
- Secrets are encrypted at rest in etcd. The rest of etcd is not.

**A free control plane with no SLA and no audit log is not the same product
as a $73/month one.** Production pays for Dedicated 4; dev and staging do
not.

## Against EKS, GKE and AKS

| | Kapsule | EKS / GKE / AKS |
| --- | --- | --- |
| Node-less mode | none | Autopilot, Fargate |
| Node autoscaling | cluster-autoscaler | + Karpenter, NAP, node auto-provisioning |
| Discounted capacity | savings plans, 10–25% against 1–3 years | Spot at 70–90% off, plus committed-use discounts |
| Workload identity | **none** | WIF, Pod Identity, Workload Identity |
| Private control plane | **impossible** | standard on all three |
| Managed backup | none | Backup for GKE, AWS Backup, AKS Backup |
| Managed Gateway API | none | GKE controller, ALB controller, AGC |
| Node access | SSH on by default, can be disabled | none on Autopilot, full on the rest |
| Cluster ceiling | 150–500 nodes | thousands |
| Regions | 3, all EU | tens, worldwide |
| Control plane price | free, or €80–256/mo | ~$73/mo, flat |

Absences are absences. The socle covers backup with Velero and exposure with
an in-cluster controller on every cloud already, so those two cost Scaleway
nothing. Identity and the private control plane do cost it something, and
both land in the network and security work.

## CNI: Cilium, but not ours

Kapsule supports **cilium** (default) and **calico**. The API enum also
carries `none` and `cilium_native`; neither is documented as supported, so
neither is a plan.

Scaleway operates the CNI as a system add-on, alongside CoreDNS, kube-proxy
and the CSI driver. The practical consequences:

- **The Cilium version is Scaleway's.** No pinning, no matching the version
  the catalog validates on the other three clouds.
- **kube-proxy stays.** Scaleway ships and manages it, so Cilium runs
  beside it rather than replacing it. The eBPF kube-proxy replacement Socle
  gets elsewhere is not available here.
- **Hubble is not shipped.** No relay, no UI, no flow visibility out of the
  box.
- **It is tunable, not replaceable.** `CiliumNodeConfig` is honoured —
  Scaleway documents enabling WireGuard encryption that way, which is the
  supported path for per-node Cilium settings.

So Cilium-on-four-clouds is true on the box and false in the detail: three
clouds run the socle's Cilium, Scaleway runs Scaleway's.

## Autoscaling

Kapsule runs the upstream cluster-autoscaler, configured on the cluster and
scaled per pool. **There is no Karpenter for Scaleway** — no provider
exists, official or community — so there is nothing to install and nothing
to refuse.

| | cluster-autoscaler, here | Karpenter, elsewhere |
| --- | --- | --- |
| Unit of scaling | the pool, one instance type | the Pod's actual requirements |
| Instance type | **ours to choose, per pool** | the controller's |
| Consolidation | **none** | repacks, replaces nodes with cheaper ones |
| Scale to zero | yes, `min_size = 0` | yes |
| Spot | nothing to handle | interruption, fallback, spot-to-spot |

**What is lost is consolidation, not spot.** The autoscaler removes a node
once it falls below the utilisation threshold and its Pods fit elsewhere; it
never replaces a running node with a cheaper one. That repacking is
Karpenter's main saving on a pure on-demand estate, and it has no equivalent
here.

**So pool shape is a design act.** Several workload shapes mean several
pools, each carrying its own `min_size` floor, and every floor is billed
whether or not anything schedules on it.

Everything is tunable on the cluster: `scale_down_unneeded_time` (10m),
`scale_down_utilization_threshold` (0.5), `scale_down_delay_after_add`
(10m), `max_graceful_termination_sec` (600), `estimator` (binpacking),
`expander` (**random**), `balance_similar_node_groups`,
`ignore_daemonsets_utilization`, `skip_nodes_with_local_storage`,
`expendable_pods_priority_cutoff`.

**`expander = "least_waste"` is a module default, because Scaleway ships
`random`.** With more than one pool, the shipped default picks which pool to
grow by coin flip. `least_waste` picks the one that strands the least
capacity. `price` is also in the enum and is not used — upstream implements
it for GCE and AWS only.

## Instance types and zones

The constraint that shapes the estate, and it is documented nowhere as such.
It comes out of the Instances API.

**Scaleway is mid-generation change, and the two generations never share a
zone.**

| Zone | POP2 / POP2-HC / PRO2 | COMPUTE3 / BASIC3, Zen 5 | GPU |
| --- | --- | --- | --- |
| fr-par-1 | — | yes | L4 |
| fr-par-2 | — | yes | H100, B300 |
| fr-par-3 | yes | — | — |
| nl-ams-1 | — | yes | — |
| nl-ams-2 | POP2 only | yes | — |
| nl-ams-3 | yes | — | — |
| pl-waw-1 | yes | — | — |
| pl-waw-2 | yes | — | H100, L4, L40S |
| pl-waw-3 | yes | — | — |

Read from `/instance/v1/zones/{zone}/products/servers`, 14 September 2026.
**Scaleway's own documentation disagrees**, listing POP2 in PAR1 and PAR2
where the API offers none. The API is what a `tofu apply` meets; re-check it
at onboarding.

What follows from it:

- **Only pl-waw can run a homogeneous three-AZ cluster.** fr-par and nl-ams
  each carry the modern range in two zones and the previous one in the third.
- **Three AZs in fr-par means mixing generations** — COMPUTE3 in par-1 and
  par-2, POP2-HC in par-3 — across hardware Scaleway itself claims is 35%
  apart, and which `balance_similar_node_groups` will not treat as similar.
- **GPU sits with the modern range**, in fr-par-1 and fr-par-2, and in
  pl-waw only in waw-2. A GPU pool next to par-3's POP2-HC is impossible.

**Decision: COMPUTE3-X across fr-par-1 and fr-par-2. Two zones, not three.**

- Dedicated vCPU at 1:2, the estate's own ratio, on current hardware, in the
  region a client buying European sovereignty actually asked for.
- **BASIC3-X is refused for nodes.** Shared vCPU and a 99% SLO against 99.5%
  for the dedicated ranges. It is cheaper — €130 against €171 for 8 vCPU /
  16 GiB — and it is not what a production node is.
- **pl-waw on POP2-HC is the catalog option** when three availability zones
  are a hard requirement, at the cost of the previous hardware generation.

## GPU

**Delegated, entirely.** Scaleway installs the NVIDIA GPU operator on every
GPU pool by default — device plugin, container toolkit, drivers. Nothing for
the catalog to ship, nothing for the factory to maintain.

- The trap is Scaleway's own: the operator installs drivers *after* the node
  registers, so a workload scheduling immediately misses them. Startup
  taints are the answer and Kapsule supports them per pool.
- Quotas are low and identity-gated — 3 H100 nodes, 5 L4 or L40S.

## Versions and upgrades

- A minor lands in Kapsule within days to weeks of upstream. There are **no
  release channels** — no Rapid/Regular/Stable to stagger an estate behind.
- **Support is 14 months per minor**, longer than upstream's own window and
  with no paid extension to buy. Two upgrades a year is the floor.
- **Auto-upgrade covers patches only**, inside the current minor, in a
  maintenance window you set. Minor upgrades are a deliberate act.
- At end of support Scaleway upgrades the cluster to the next minor within
  30 days, announced by ticket.

That is a cleaner deal than GKE's channels and EKS's paid extended support:
one clock, no tier to buy, and the minor upgrade stays ours to schedule.
The missing piece is ring ordering — with no channel to skew, the order of
dev → staging → prod is entirely the pipeline's to enforce.

## Identity

IAM principals are users, groups and applications. An application holds an
API key; there is no trust relationship a Kubernetes ServiceAccount token
can be exchanged against.

- **A Pod that calls the Scaleway API carries a static secret.** Rotation is
  ours to build. This is the single largest gap against the other three
  clouds, and it is the reason the Scaleway module provisions an IAM
  application and key where the GCP module provisions a binding.
- IAM does reach *into* the cluster: permission sets map onto Kubernetes
  groups (`KubernetesFullAccess` → `scaleway:cluster-write`,
  `KubernetesReadOnly` → `scaleway:cluster-read`), and each IAM group
  becomes `scaleway:group:GROUPID`. Human access is solved. Workload access
  is not.

## Networking

Decided here, because no other ticket in the Scaleway sprint owns it.

| Question | Position |
| --- | --- |
| Node isolation | Full isolation, every environment |
| Public Gateways | One per AZ the cluster's pools span |
| Control plane exposure | Allowed-IP list, required, never `0.0.0.0/0` |
| Security group | One per cluster, created by the module |
| Layout | One VPC per environment, one /22 Private Network per cluster |
| Node spread | One pool per AZ, each in its own placement group |

**Full isolation everywhere.** Nodes carry no public IP and egress leaves
through a Public Gateway, which matches the private-node position already
taken on AWS and GCP and yields a stable egress IP to allow-list elsewhere.
Controlled isolation is free and drops inbound traffic anyway, but it would
have dev and staging exercising a different egress path from production —
the one thing the socle exists to prevent.

**One gateway per Availability Zone.** The Public Gateway is zoned and has
no HA. Scaleway is explicit: a gateway in PAR-1 serving nodes in PAR-2 and
PAR-3 stops serving them when PAR-1 fails, and the documented workaround is
several gateways on one Private Network, each advertising a default route.
One gateway is functionally enough for a whole region; surviving a zone
outage takes one per zone the cluster actually spans. On the default
two-zone fr-par layout that is **two in production**, one each in dev and
staging — three in production only on the pl-waw option. The ceilings are 10
Private Networks per gateway and 50 gateways per Organization.

- The dependency is hard in both directions: detach the gateways and the
  nodes lose their route to the control plane.

**The allowed-IP list is required, with no default.** The control plane
cannot be made private, so this list is the only boundary that exists — and
`0.0.0.0/0` is what Kapsule ships. A variable with no default is the only
way to make someone decide. It carries the pipeline's egress and the
operators', nothing else.

**A security group per cluster.** New clusters are attached to a
`Kapsule default security group` that is **shared between clusters**:
editing it to open a port on one cluster opens it on all of them.
`security_group_id` is settable at creation, so the module sets it.

**One VPC per environment, one Private Network per cluster.** Routing is
VPC-wide, so a single VPC makes every cluster routable from every other. The
/22 belongs to the cluster and its range is the module's to choose.

**A placement group per pool.** Multi-AZ is one pool per zone; inside a
zone, nothing otherwise stops a pool's nodes landing on one hypervisor.

A zone-redundant API server still requires a dedicated control plane —
production has one, dev and staging do not.

## Observability

Cockpit is Grafana over Mimir and Loki. **Scaleway's own data — control
plane metrics and logs, node metrics, audit logs — is free**, retained 31
days for metrics and 7 for logs.

Custom data is not free, and the rate is the finding:

| | Kapsule / Cockpit | GKE / Managed Prometheus |
| --- | --- | --- |
| Workload metrics | €0.15 per million samples | $0.158 per sample/second per month |
| Same, per sample/second per month | **€0.39** | $0.158 |

A cluster filtered to the ~300 samples/second the catalog scrapes costs
**~€118/month on Cockpit** against $47 on GKE — roughly 2.5× per sample.
Self-hosting Prometheus on nodes already paid for is the cheaper side of a
crossover that sits much lower here than on GCP.

**The recommendation: take Scaleway's free data through Cockpit, keep
workload metrics in the socle's own Prometheus.** The reverse of the GCP
position, for the same reason — the price per sample.

Ingestion caps to respect either way: Mimir 25,000 samples/s and 1M active
series per data source, Loki 4 MB/s.

## Cost

The sprint's reference estate: prod 20 vCPU / 40 GiB of Pod requests,
staging 8 / 16, dev 4 / 8.

Kapsule bills nodes, not requests. Sizing rule: COMPUTE3-X (1 vCPU : 2 GiB,
the estate's own ratio), capacity covering requests plus 25% for kubelet
reserve, system daemons and rollout headroom, rounded to whole nodes.

| | Nodes | Per month |
| --- | --- | --- |
| prod | 4 × COMPUTE3-X8C-16G | €684 |
| staging | 2 × COMPUTE3-X6C-12G | €256 |
| dev | 2 × COMPUTE3-X4C-8G | €171 |
| Dedicated 4 control plane, prod only | | €80 |
| One LB-S per cluster | | €50 |
| Public Gateways — 2 in prod, 1 each elsewhere | 4 × VPC-GW-S | €76 |
| **Total** | | **~€1,317** |

- The same estate on GKE Autopilot is **$1,488/month**. Kapsule comes out
  lower, but the two bill different things — Autopilot charges the 32 vCPU
  of requests, Kapsule charges the 52 vCPU of nodes those requests need.
- **This sizing does not survive a zone loss, and two zones make that
  expensive.** With production split across fr-par-1 and fr-par-2, surviving
  the loss of one means each zone carrying the whole estate: eight nodes,
  **+€684/month**, a doubling. The same resilience on pl-waw's three zones
  costs six POP2-HC nodes, **+€311** — half as much. **Zone count, not node
  price, is what resilience costs here.**
- Node prices read from the Instances API, 14 September 2026; COMPUTE3-X is
  ~10% dearer than the POP2-HC shape it replaces.
- Persistent volumes are extra at €0.095/GB/month (5K IOPS).
- **There is no Spot line to save.** The only discount Scaleway sells is a
  savings plan: compute only, 12 or 36 months, €50 to €9,999 a month, billed
  in full whether the commitment is used or not, neither cancellable nor
  exchangeable. **The rate is bracketed by amount and duration and is not
  published** — Scaleway's worked example gives 10% for €900/month over
  three years, its Compute Optimized page advertises up to 25%. GPU
  instances are excluded outright. A commercial decision per client, never a
  module default.

fr-par list price excluding VAT, read 14 September 2026.

## Position

- **Kapsule is the foundation for Scaleway. Kosmos is refused** — a
  different CNI (Kilo), no Private Network, no migration path either way,
  and nothing in the socle needs multi-cloud nodes under one control plane.
- **Production runs a Dedicated 4 control plane. Dev and staging run
  mutualized.** The SLA and the audit log are the reason; the 200 MB etcd
  is the margin.
- **Workload metrics stay in the socle's Prometheus**, Scaleway's own data
  comes free through Cockpit.
- **Cilium is Scaleway's on this cloud.** The catalog must not assume
  Hubble or the kube-proxy replacement anywhere it wants to stay portable.
- **Full isolation everywhere, one Public Gateway per AZ, and an allowed-IP
  list with no default** — argued in [networking](#networking).
- **COMPUTE3-X across fr-par-1 and fr-par-2**, two zones rather than three,
  because the modern instance range and the previous one never share a zone.
  pl-waw on POP2-HC is the option when three zones are required.
- **`expander = "least_waste"`**, because Scaleway's cluster-autoscaler
  ships `random` and the estate runs more than one pool.

Deferred to the rest of the sprint: the upgrade ring mechanism (managed
scope), the samples/second budget (supervision), and how the Crossplane
identity's API key is rotated (foundations module).

## Sources

Read 14 September 2026.

[Control plane offers][cp] · [version support policy][versions] ·
[shared responsibility model][srm] · [Kubernetes FAQ][faq] ·
[concepts][concepts] · [Private Network][pn] · [multi-AZ][multiaz] ·
[IAM and RBAC][rbac] · [audit logs][audit] · [allowed IPs][allowed] ·
[etcd space recovery][etcd] · [Cilium encryption on Kapsule][cilium-enc] ·
[Public Gateway FAQ][pgw-faq] · [VPC concepts][vpc] ·
[General Purpose range][gp-range] · [Specialized range][spec-range] ·
[NVIDIA GPU operator on Kapsule][gpu-op] · [savings plans][savings] ·
[cluster-autoscaler options][tf-cluster] ·
`GET /instance/v1/zones/{zone}/products/servers` for what each zone
actually offers, and its prices.
[organization quotas][quotas] · [Cockpit pricing][cockpit-price] ·
[Cockpit limits][cockpit-limits] · [Kapsule pricing][k8s-price] ·
[Instances pricing][inst-price] · [Network pricing][net-price] ·
[Storage pricing][sto-price].

[cp]: https://www.scaleway.com/en/docs/kubernetes/reference-content/kubernetes-control-plane-offers/
[versions]: https://www.scaleway.com/en/docs/kubernetes/reference-content/version-support-policy/
[srm]: https://www.scaleway.com/en/docs/kubernetes/reference-content/kubernetes-shared-responsibility-model/
[faq]: https://www.scaleway.com/en/docs/kubernetes/faq/
[concepts]: https://www.scaleway.com/en/docs/kubernetes/concepts/
[pn]: https://www.scaleway.com/en/docs/kubernetes/reference-content/secure-cluster-with-private-network/
[multiaz]: https://www.scaleway.com/en/docs/kubernetes/reference-content/multi-az-clusters/
[rbac]: https://www.scaleway.com/en/docs/kubernetes/reference-content/set-iam-permissions-and-implement-rbac/
[audit]: https://www.scaleway.com/en/docs/kubernetes/how-to/access-audit-logs/
[allowed]: https://www.scaleway.com/en/docs/kubernetes/how-to/manage-allowed-ips/
[etcd]: https://www.scaleway.com/en/docs/kubernetes/how-to/recover-space-etcd/
[cilium-enc]: https://www.scaleway.com/en/docs/tutorials/enabling-encryption-in-kapsule-with-cilium/
[pgw-faq]: https://www.scaleway.com/en/docs/public-gateways/faq/
[vpc]: https://www.scaleway.com/en/docs/vpc/concepts/
[gp-range]: https://www.scaleway.com/en/docs/instances/reference-content/general-purpose/
[spec-range]: https://www.scaleway.com/en/docs/instances/reference-content/specialized/
[gpu-op]: https://www.scaleway.com/en/docs/kubernetes/how-to/use-nvidia-gpu-operator/
[savings]: https://www.scaleway.com/en/docs/billing/additional-content/understanding-savings-plans/
[tf-cluster]: https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/resources/k8s_cluster
[quotas]: https://www.scaleway.com/en/docs/organizations-and-projects/additional-content/organization-quotas/
[cockpit-price]: https://www.scaleway.com/en/docs/cockpit/reference-content/cockpit-pricing/
[cockpit-limits]: https://www.scaleway.com/en/docs/cockpit/reference-content/cockpit-limitations/
[k8s-price]: https://www.scaleway.com/en/pricing/containers/
[inst-price]: https://www.scaleway.com/en/pricing/virtual-instances/
[net-price]: https://www.scaleway.com/en/pricing/network/
[sto-price]: https://www.scaleway.com/en/pricing/storage/
