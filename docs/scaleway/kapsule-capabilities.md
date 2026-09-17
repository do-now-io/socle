# Kapsule: capabilities and limits

What Kapsule does, what it cannot do, and the constraints the foundations
module has to absorb. The network baseline is decided here — the Scaleway
sprint has no separate ticket for it.

**Kapsule is a viable foundation. Four of its limits are structural: the
module is shaped around them, not against them.**

| Question | Position |
| --- | --- |
| Product | Kapsule — Kosmos refused, different CNI, no Private Network |
| Control plane, production | Dedicated 4 — the SLA and the audit log |
| Control plane, dev and staging | Mutualized, free |
| CNI | Cilium, Scaleway's own — not pinnable, no Hubble |
| Node autoscaling | cluster-autoscaler — no Karpenter exists for Scaleway |
| Node range and zones | COMPUTE3-X, fr-par-1 and fr-par-2 |
| Minor versions | Ours — auto-upgrade covers patches only |
| Node isolation | Full isolation, every environment |
| Control plane exposure | Allowed-IP list, required, no default |
| Workload metrics | The socle's Prometheus — Cockpit bills per sample |

## The four structural limits

| Limit | Consequence |
| --- | --- |
| No workload identity federation | Pods authenticate with a long-lived API key held as a Secret |
| The control plane always has a public IP | No private cluster; an IP allow-list is the only boundary |
| etcd capped at 55 MB mutualized, 200 MB dedicated | A CRD-heavy socle is a sizing input, not a detail |
| No spot market, no Karpenter | Fixed node types under cluster-autoscaler; savings plans are the only discount |

None has a workaround inside the cluster. They are priced and designed for,
or the cluster is not run on Scaleway.

## Control plane

| | Mutualized | Dedicated 4 | Dedicated 8 |
| --- | --- | --- | --- |
| Price | **free** | €80/mo | €131/mo |
| SLA | **none** | 99.5% | 99.5% |
| Audit logs | **no** | yes | yes |
| API server | 1 replica | 2, HA | 2, HA |
| Max nodes / etcd | 150 / 55 MB | 250 / 200 MB | 500 / 200 MB |

**Decision: Dedicated 4 in production, mutualized in dev and staging.** A
free control plane with no SLA and no audit log is not the same product. The
tier carries a 30-day commitment, and a zone-redundant API server requires a
dedicated tier at all.

## What Kapsule does not have

No workload identity, no private control plane, no node-less mode, no spot
market, no managed backup, no managed Gateway API, and a ceiling of 150 to
500 nodes across three EU regions.

Most of those cost nothing: Velero and an in-cluster ingress controller are
the socle's standard everywhere, and the node ceiling is far above any estate
the offer targets. **Identity and the public control plane are the two that
cost something**, and both land in the module.

What it gives back: a free control plane, Cilium as the default, API-server
knobs (`feature_gates`, `admission_plugins`, OIDC) that a fully managed
cluster does not expose, and an EU-only footprint with a French operator —
which for a client buying sovereignty is the product.

## CNI

Cilium is the default and Scaleway operates it as a system add-on, beside
CoreDNS, kube-proxy and the CSI driver. Calico is the only alternative;
`none` is not supported.

**So Cilium here is true on the box and false in the detail.** The version is
Scaleway's, kube-proxy stays (no eBPF replacement), and Hubble is not
shipped. `CiliumNodeConfig` is honoured, so it is tunable, not replaceable.
**The catalog must treat Scaleway as the cloud where Cilium's own features
are unavailable**, not as the cloud where Cilium is free.

## Autoscaling and node shape

Upstream cluster-autoscaler, configured per pool. There is no Karpenter for
Scaleway — nothing to install, nothing to refuse.

**What is lost is consolidation, not spot.** The autoscaler removes an
under-used node; it never replaces a running node with a cheaper one. So
**pool shape is a design act**: several workload shapes mean several pools,
each with a `min_size` floor billed whether or not anything schedules on it.

**`expander = "least_waste"` is a module default, because Scaleway ships
`random`** — with more than one pool, the shipped default grows one by coin
flip.

**Decision: COMPUTE3-X across fr-par-1 and fr-par-2. Two zones, not three.**

- **The current and previous instance generations never share a zone.** Read
  from the Instances API, which disagrees with Scaleway's own documentation —
  re-check it at onboarding. Only pl-waw can run a homogeneous three-zone
  cluster; three zones in fr-par would mix hardware 35% apart.
- BASIC3-X is refused for nodes: shared vCPU, 99% SLO against 99.5%.
- pl-waw on POP2-HC is the catalog option when three zones are a hard
  requirement, at the cost of the previous generation.
- GPU is delegated entirely — Scaleway installs the NVIDIA operator on every
  GPU pool. Startup taints are needed, since drivers land after the node
  registers.

## Versions and upgrades

- A minor lands within days to weeks of upstream. **No release channels**, so
  no channel skew to stagger an estate behind.
- **14 months of support per minor**, with no paid extension to buy. Two
  upgrades a year is the floor.
- **Auto-upgrade covers patches only.** Minors are a deliberate act, and at
  end of support Scaleway upgrades within 30 days anyway.

One clock and no tier to buy. The missing piece is ring ordering: with no
channel to skew, dev → staging → prod is entirely the pipeline's to enforce.

## Networking

| Question | Position |
| --- | --- |
| Node isolation | Full isolation, every environment |
| Public Gateways | One per AZ the cluster's pools span |
| Control plane exposure | Allowed-IP list, required, never `0.0.0.0/0` |
| Security group | One per cluster, created by the module |
| Layout | One VPC per environment, one /22 Private Network per cluster |
| Node spread | One pool per AZ, each in its own placement group |

**Full isolation everywhere.** Nodes carry no public IP, egress leaves through
a Public Gateway, and the egress IP is stable enough to allow-list elsewhere.
Controlled isolation is free, but it would have dev exercising a different
egress path from production — the one thing the socle exists to prevent.

**One gateway per Availability Zone.** The Public Gateway is zoned and has no
HA; Scaleway's own answer to a zone outage is several gateways on one Private
Network. Two in production on the fr-par layout, one each in dev and staging.
The dependency is hard: detach the gateways and the nodes lose their route to
the control plane.

**The allowed-IP list is required, with no default.** The control plane
cannot be made private, so this list is the only boundary that exists — and
`0.0.0.0/0` is what Kapsule ships. It carries the pipeline's egress and the
operators', nothing else.

**One security group per cluster**, because the default one is shared between
clusters: opening a port on one opens it on all of them. **One VPC per
environment**, because routing is VPC-wide.

## Observability

Cockpit is Grafana over Mimir and Loki. **Scaleway's own data — control plane
metrics and logs, node metrics, audit logs — is free**, retained 31 days.

Custom data is not, and the rate is the finding: €0.15 per million samples,
so the ~300 samples/s the catalog scrapes costs **~€118/month per cluster**.
That is more than running Prometheus on nodes already paid for.

**Decision: Scaleway's free data through Cockpit, workload metrics in the
socle's own Prometheus.** Pulling the free data out is
[cloud observability](cloud-observability.md).

## Cost

Reference estate: prod 20 vCPU / 40 GiB of Pod requests, staging 8 / 16, dev
4 / 8. Kapsule bills nodes, not requests — sizing covers requests plus 25%
for reserve and rollout headroom.

| | Per month |
| --- | --- |
| Nodes — COMPUTE3-X, 4 + 2 + 2 | €1,111 |
| Dedicated 4 control plane, prod only | +€80 |
| One Load Balancer per cluster | +€50 |
| Public Gateways — 2 in prod, 1 each elsewhere | +€76 |
| **Total** | **~€1,317** |
| *Production surviving a zone loss, on two zones* | *+€684* |
| *The same, on pl-waw's three zones* | *+€311* |

- **Kapsule bills the 52 vCPU of nodes the 32 vCPU of requests need**, so
  headroom is paid for, not absorbed.
- **Zone count, not node price, is what resilience costs here.** On two zones
  each must carry the whole estate; a doubling.
- **No Spot line to save.** Savings plans are compute-only, 12 or 36 months,
  billed in full used or not, neither cancellable nor exchangeable, and the
  rate is unpublished. A commercial decision per client, never a module
  default.

fr-par list price excluding VAT, read 14 September 2026.

## Sources

Read 14 September 2026. [Control plane offers][cp] · [version support
policy][versions] · [shared responsibility model][srm] · [Private
Network][pn] · [multi-AZ][multiaz] · [IAM and RBAC][rbac] · [allowed
IPs][allowed] · [Cilium encryption on Kapsule][cilium-enc] · [Public Gateway
FAQ][pgw-faq] · [VPC concepts][vpc] · [NVIDIA GPU operator][gpu-op] ·
[savings plans][savings] · [cluster-autoscaler options][tf-cluster] ·
[Cockpit pricing][cockpit-price] · [Kapsule][k8s-price], [Instances][inst-price],
[Network][net-price] and [Storage][sto-price] pricing. Zone-by-zone instance
availability comes from `GET /instance/v1/zones/{zone}/products/servers`.

[cp]: https://www.scaleway.com/en/docs/kubernetes/reference-content/kubernetes-control-plane-offers/
[versions]: https://www.scaleway.com/en/docs/kubernetes/reference-content/version-support-policy/
[srm]: https://www.scaleway.com/en/docs/kubernetes/reference-content/kubernetes-shared-responsibility-model/
[pn]: https://www.scaleway.com/en/docs/kubernetes/reference-content/secure-cluster-with-private-network/
[multiaz]: https://www.scaleway.com/en/docs/kubernetes/reference-content/multi-az-clusters/
[rbac]: https://www.scaleway.com/en/docs/kubernetes/reference-content/set-iam-permissions-and-implement-rbac/
[allowed]: https://www.scaleway.com/en/docs/kubernetes/how-to/manage-allowed-ips/
[cilium-enc]: https://www.scaleway.com/en/docs/tutorials/enabling-encryption-in-kapsule-with-cilium/
[pgw-faq]: https://www.scaleway.com/en/docs/public-gateways/faq/
[vpc]: https://www.scaleway.com/en/docs/vpc/concepts/
[gpu-op]: https://www.scaleway.com/en/docs/kubernetes/how-to/use-nvidia-gpu-operator/
[savings]: https://www.scaleway.com/en/docs/billing/additional-content/understanding-savings-plans/
[tf-cluster]: https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/resources/k8s_cluster
[cockpit-price]: https://www.scaleway.com/en/docs/cockpit/reference-content/cockpit-pricing/
[k8s-price]: https://www.scaleway.com/en/pricing/containers/
[inst-price]: https://www.scaleway.com/en/pricing/virtual-instances/
[net-price]: https://www.scaleway.com/en/pricing/network/
[sto-price]: https://www.scaleway.com/en/pricing/storage/
