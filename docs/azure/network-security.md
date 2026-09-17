# AKS network & security baseline

Who manages what across upgrades, add-ons, and identity — see
[managed scope](managed-scope.md). This document covers the network and
security baseline: CNI dataplane, exposure, cluster access, the reference
VNet/subnet/NAT layout, and Microsoft Defender for Containers.

| Question | Position |
| --- | --- |
| CNI dataplane | Self-managed Cilium, not the managed "Azure CNI powered by Cilium" |
| Pod IPAM | Cilium's own, decoupled from the VNet |
| Network policy | Full Cilium L3/L4/L7 — no paid add-on gating it |
| Exposure | Gateway API via the app routing add-on (in-cluster Istio) |
| Application Gateway for Containers | Catalog option, not default |
| Cluster access | Private cluster, public FQDN disabled |
| Reference network | One VNet per environment, private node subnet, NAT Gateway |
| Microsoft Defender for Containers | Catalog option, not default |

## 1. CNI: self-managed Cilium

**Decision.** Self-managed Cilium through AKS's BYO CNI path
(`--network-plugin none`), not the managed "Azure CNI powered by Cilium."

- The managed variant locks the Cilium ConfigMap to label-exclusion edits
  only, can't select node or pod IPs in a NetworkPolicy `ipBlock`, and is
  Linux-only. More importantly, FQDN filtering, L7 (HTTP/gRPC/Kafka)
  policies, WireGuard/mTLS encryption, and flow-level observability are
  all gated behind Advanced Container Networking Services (ACNS), a paid
  add-on billed per node.
- Self-managed Cilium is Microsoft's own documented path for exactly this
  case — "customers who need more control." It gets the full open-source
  feature set for free, with nothing gated behind a separate add-on.
- The trade: Microsoft support excludes CNI-level issues on a BYO CNI
  cluster (pod-to-pod traffic, CNI plugin bugs). Node health and the
  control plane stay fully supported either way.

**IPAM.** BYO CNI hands pod IP allocation, routing, and scaling entirely to
Cilium — AKS never allocates pod IPs or pre-assigns per-node pod CIDRs.
The VNet subnet only needs to be sized for nodes, plus headroom for surge
upgrades and internal load balancers — pod count never factors into
subnet sizing, the same practical outcome Overlay would have given, for a
different reason.

A `serviceCIDR`, a `dnsServiceIP`, and a pod CIDR value are still required
at cluster creation regardless of CNI choice — the control plane routes to
pods using that value even though Cilium is what actually assigns pod IPs.

## 2. Exposure: Gateway API via app routing, not Application Gateway for Containers

**Decision.** The app routing add-on's Gateway API implementation —
an in-cluster Istio control plane, GA.

- Runs as pods (`istiod` plus a proxy deployment per Gateway, autoscaled
  2–5 replicas with a PodDisruptionBudget) — cost is compute already
  counted in the estate, nothing new to provision.
- Application Gateway for Containers (AGC) is also GA and technically
  richer — WAF, mTLS, AI-inference-aware routing — but runs as a separate
  Azure resource with a fixed hourly cost regardless of traffic: Frontend
  + Association + the AGC resource itself run **~$134/month minimum per
  Gateway**, before any Capacity Unit or WAF policy is added.
- Both speak the same Gateway API surface (`Gateway`, `HTTPRoute`), so a
  client that later needs AGC's extra features isn't rewriting anything —
  AGC stays a catalog option, not refused.

Real limitation to flag: the app routing Gateway API implementation can't
do request header/body size limits, Lua scripts, or rate limiting — Gateway
API has no standard field for them. A client needing those falls back to
the Istio service mesh add-on (same Gateway API surface, a different
GatewayClass), at the cost of canary-style minor-version upgrades instead
of in-place ones.

## 3. Cluster access: private cluster, public FQDN disabled

**Decision.** Private cluster, public FQDN disabled.

- Nodes already sit in a private subnet behind NAT (below) — a publicly
  reachable control plane would be the one remaining public surface.
  AKS's private-cluster pattern (a Private Link endpoint plus a private
  DNS zone, both in the node's own resource group) removes it entirely.
- Cost: one Private Endpoint per cluster, ~$0.01/hour ($7.30/month) plus
  $0.01/GB processed — negligible next to the control plane itself.
- IP-authorized ranges only ever applied to the public endpoint anyway —
  going fully private doesn't give up a filtering capability, it removes
  the surface that filtering would have applied to.
- Admin access goes through VPN, ExpressRoute, VNet peering, or Bastion —
  the same access pattern already assumed for reaching nodes on a
  private-subnet cluster.
- Private DNS zone stays AKS-managed (`system`) by default — a custom
  zone only matters for hub-and-spoke DNS forwarding, a per-client
  network decision, not a module default.

## 4. Reference network: VNet, subnets, NAT

**Decision.** One VNet per environment, one private node subnet sized for
nodes only (never pods, since Cilium owns pod IPAM), NAT Gateway for
egress.

| Range | Sizing consideration |
| --- | --- |
| Node subnet | Max nodes per pool + surge-upgrade headroom + internal load balancer IPs |
| Service CIDR | Smaller than `/12`, never overlapping the VNet or a connected network |
| Pod CIDR | Still declared at creation for control-plane routing, even though Cilium assigns the real pod IPs |

NAT Gateway: $0.045/hour ($32.85/month) plus $0.045/GB processed, priced
flat regardless of region — one per environment, for the same node egress
traffic (image pulls, package installs) private subnets always need.

## 5. Microsoft Defender for Containers: catalog option

**Decision.** Not default — exposed as a catalog option.

- Never bundled into any AKS tier. Free/Standard/Premium are a
  control-plane axis (SLA, Long-Term Support) — an entirely separate
  thing from Defender. Defender for Containers is a Microsoft Defender
  for Cloud plan, toggled at the subscription level, billed per vCore:
  $0.00941/vCore/hour (~$6.87/vCore/month).
- Real cost at estate scale: on the reference estate (36 vCPU across
  three environments), that's **~$247/month** — not a "free, not
  disableable" delegation, so it's an explicit choice like the module's
  other priced options, not a bundled default.
- Whether a given client gets it is a packaging decision (a higher-tier
  offer turning it on, a base offer not) — the module exposes the
  variable so that choice is made per client, not baked into the
  module's default.

## What this module does and doesn't do

Cilium itself isn't installed by this module — same as Karpenter, the CSI
drivers, and the load balancer controller on the other clouds, it's a
factory component delivered by the socle OCI artifact through GitOps. The
module's job stops at making the cluster ready for it: `network_plugin`
set to `none`, the CIDRs above, and the private-cluster settings.

## Sources

Read September 2026, France Central pricing where applicable.

[Azure CNI Powered by Cilium][cilium-managed] ·
[Azure CNI Overlay][overlay] · [BYO CNI][byo-cni] ·
[Advanced Container Networking Services pricing][acns-pricing] ·
[Application Gateway for Containers overview][agc] ·
[App routing Gateway API implementation][app-routing-gwapi] ·
[Private AKS clusters][private-clusters] ·
[Defender for Containers deployment overview][defender] ·
[Free/Standard/Premium pricing tiers][aks-tiers] ·
[Azure Retail Prices API][retail-prices].

[cilium-managed]: https://learn.microsoft.com/en-us/azure/aks/azure-cni-powered-by-cilium
[overlay]: https://learn.microsoft.com/en-us/azure/aks/azure-cni-overlay
[byo-cni]: https://learn.microsoft.com/en-us/azure/aks/use-byo-cni
[acns-pricing]: https://azure.microsoft.com/en-us/pricing/details/advanced-container-networking-services/
[agc]: https://learn.microsoft.com/en-us/azure/application-gateway/for-containers/overview
[app-routing-gwapi]: https://learn.microsoft.com/en-us/azure/aks/app-routing-gateway-api
[private-clusters]: https://learn.microsoft.com/en-us/azure/aks/private-clusters
[defender]: https://learn.microsoft.com/en-us/azure/defender-for-cloud/defender-for-containers-deployment-overview
[aks-tiers]: https://learn.microsoft.com/en-us/azure/aks/free-standard-pricing-tiers
[retail-prices]: https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices
