# GKE cluster mode: Autopilot vs Standard

## Decision

**Socle provisions GKE Autopilot clusters. Standard is not offered.**

The `opentofu/gcp` module has no cluster mode option. If you need Standard
— a CNI other than GKE Dataplane V2, node-level access, privileged Pods,
a node OS other than Container-Optimized OS — Socle is not the right
foundation for that cluster, and the module will not pretend otherwise.

This page exists because the decision is not free: **Autopilot costs more
in raw compute than a well-packed Standard cluster.** The numbers below
are the ones that led to the choice anyway.

## The two modes

|  | Autopilot | Standard |
| --- | --- | --- |
| Nodes | Google provisions and operates them | You own them |
| Billing | Pod resource requests | Node capacity, used or idle |
| Node upgrades, patching, repair | Google | You, or automated by you |
| CNI | Dataplane V2, enforced | Your choice |
| Node access | None | Full |
| Hardening defaults | Workload Identity, Shielded nodes, network policy all on | Off unless you enable them |

Mode is fixed at creation. Changing it means building a second cluster
and migrating.

## What it costs

### Assumptions

```
Priced        2026-09, us-central1, list price, no committed-use discount
Month         730 hours
Reference app 2 replicas x (250 mCPU + 512 MiB) = 0.5 vCPU + 1 GiB requested
Platform      Socle's own components, estimated at 2 vCPU + 4 GiB

Autopilot     $0.0445 / vCPU-hour        -> $32.49 / vCPU-month
              $0.0049225 / GiB-hour      -> $3.59 / GiB-month
Cluster fee   $0.10 / hour               -> $73.00 / month   (both modes)
Standard      e2 custom nodes, 8 vCPU / 16 GiB, matched to the 1:2
              workload ratio: $161 / node-month, of which 7.91 vCPU and
              13.3 GiB are allocatable after GKE's own reservations
```

The Standard column assumes **perfect bin-packing** — every node filled
to its allocatable ceiling, no headroom, no per-environment pools, no
spare capacity for upgrades. That is the most favourable assumption
available to Standard, and it is deliberate: an argument for Autopilot
that only holds against a badly run Standard cluster is not an argument.

### Cost per month

| Deployed | Requests | Autopilot | Standard, best case |
| --- | --- | --- | --- |
| Nothing at all | — | **$73** | **$73** (zero nodes, runs nothing) |
| Platform, no apps | 2 vCPU / 4 GiB | **$152** | **$234** (1 node) |
| Platform + 10 apps | 7 vCPU / 14 GiB | **$350** | **$395** (2 nodes) |
| Platform + 100 apps | 52 vCPU / 104 GiB | **$2,136** | **$1,361** (8 nodes) |

### Reading it

**An idle Autopilot cluster is nearly free.** With no Pods, you pay the
$73 management fee and nothing else. A Standard cluster cannot idle: it
needs at least one running node to run anything, so its floor is the fee
plus a node. This is why dev and preview clusters favour Autopilot
strongly.

**The crossover is around a dozen apps.** Below it Autopilot is cheaper;
above it, a perfectly packed Standard cluster wins, by 36% at 100 apps.

Two smaller effects, both excluded above: ephemeral storage adds under 1%
on Autopilot, and Autopilot enforces a minimum request of 250 mCPU /
512 MiB per Pod. The reference app sits exactly on that floor, so nothing
is rounded up — but a cluster of many very small Pods pays the floor
regardless, which makes Autopilot a poor fit for that shape of workload.

### The Standard column is a floor, not a forecast

Eight nodes for 100 apps means every node runs at 98% of its allocatable
memory. No real cluster runs there. A rolling update needs room for surge
Pods, HPA needs room to scale into, and a node upgrade needs somewhere to
drain to. Putting that back, at 100 apps:

| Standard at 100 apps | Nodes | Utilisation | Cost | vs Autopilot |
| --- | --- | --- | --- | --- |
| Perfect packing | 8 | 98% | $1,361 | 36% cheaper |
| 25% headroom, zones balanced | 12 | 65% | $2,005 | 6% cheaper |
| ...and survives losing one zone | 18 | 43% | $2,971 | 39% dearer |

**Parity is at 61% node utilisation.** Above it Standard is cheaper on
compute; below it Autopilot is. The entire decision lives inside that
band — and where a cluster actually sits in it is not a fact about GKE.
It is a fact about how much attention someone pays to bin-packing, every
quarter, in every environment.

The third row deserves the most attention. Pre-buying idle node capacity
to absorb a zone failure is what makes a regional Standard cluster
actually regional; skip it and a zone outage becomes a capacity outage.
Autopilot has no equivalent line item, because unused capacity is not
yours to pay for.

Committed-use discounts and Spot capacity cut both columns and roughly
preserve the ratio. They are not an argument for either mode.

## Why Autopilot anyway

At realistic packing the premium at 100 apps is about **$130/month**, and
it inverts — Autopilot becomes 28% cheaper — once the cluster is sized to
survive a zone loss. Only the perfectly packed floor makes Standard
clearly cheaper. What the premium buys:

- **No node layer to operate.** No pool sizing, no autoscaler tuning, no
  node OS patch cadence, no drain-and-replace during upgrades, no
  node-pressure alerting. Node auto-provisioning automates the mechanics
  of this on Standard; it does not remove the judgement, and the
  judgement is what costs time.
- **Hardened defaults, not hardening projects.** Workload Identity,
  Shielded nodes, network policy enforcement and Pod-level restrictions
  are on and not optional. On Standard each is a task, and each is a task
  that gets skipped.
- **Utilisation you do not have to defend.** The 61% figure above is a
  standing obligation: Standard is cheaper only while someone keeps it
  packed, every quarter, across every environment.
- **One shape of cluster.** Socle ships one GCP foundation, tested one
  way. A mode switch would double the surface the module must support and
  halve how well either half is tested.

If holding every cluster above 61% utilisation, every quarter, in every
environment, is cheaper for you than that premium, Standard is the
correct choice and Socle is the wrong tool. That is a real position, not
a rhetorical one — it just is not the position this project is built
around.

## What you give up

- Dataplane V2 only. No Calico, no self-managed Cilium, no custom eBPF.
- No SSH to nodes, no host namespaces, no writable `hostPath`.
- No privileged Pods outside Google's [partner allowlists][partners] —
  check your observability vendor against that list before adopting.
- Container-Optimized OS only. No Ubuntu or Windows node pools.
- Automatic upgrades. You choose the maintenance window, not whether.

Socle's own components need none of these.

## Revisit this if

- Node utilisation across a fleet is consistently above 61% and measured,
  not assumed.
- Autopilot's per-Pod rates or the minimum request floor change
  materially.
- Running Autopilot compute classes on Standard clusters matures enough
  to offer both billing models from one cluster shape.

## Sources

- [GKE pricing][pricing] — Autopilot Pod rates, cluster management fee,
  free tier
- [Compute Engine VM pricing][vm-pricing] — e2 rates for the Standard
  column
- [Autopilot and Standard feature comparison][comparison]
- [Autopilot resource requests and limits][requests] — minimums and
  ratios
- [GKE Dataplane V2][dpv2]
- [Autopilot partner workloads][partners]

Rates were read in September 2026 for us-central1 and will drift. The
ratio between the two modes moves far less than the absolute numbers, and
the ratio is what this page is really about — but re-price before quoting
anything.

[pricing]: https://cloud.google.com/kubernetes-engine/pricing
[vm-pricing]: https://cloud.google.com/compute/vm-instance-pricing
[comparison]: https://cloud.google.com/kubernetes-engine/docs/resources/autopilot-standard-feature-comparison
[requests]: https://cloud.google.com/kubernetes-engine/docs/concepts/autopilot-resource-requests
[dpv2]: https://cloud.google.com/kubernetes-engine/docs/concepts/dataplane-v2
[partners]: https://cloud.google.com/kubernetes-engine/docs/resources/autopilot-partners
