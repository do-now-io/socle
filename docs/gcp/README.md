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

The reference estate is the one the other cloud sprints price, so that
the four comparisons stack: **a 20 vCPU production cluster, plus staging
and dev — three environments.**

```
Priced        2026-09, us-central1, list price, no committed-use discount
Month         730 hours
Reference app 2 replicas x (250 mCPU + 512 MiB) = 0.5 vCPU + 1 GiB requested
Estate        prod 20 vCPU / 40 GiB, staging 8 / 16, dev 4 / 8 requested
              (the 1:2 CPU:memory ratio comes from the reference app)

Autopilot     $0.0445 / vCPU-hour        -> $32.49 / vCPU-month
              $0.0049225 / GiB-hour      -> $3.59 / GiB-month
Cluster fee   $0.10 / hour               -> $73.00 / month   (both modes)
Standard      e2 custom nodes, 8 vCPU / 16 GiB, matched to the 1:2
              workload ratio: $161 / node-month, of which 7.91 vCPU and
              13.3 GiB are allocatable after GKE's own reservations
```

The 20 vCPU and the three environments come from the shared sprint
scenario; the staging and dev sizes are this page's own reading of it.
Memory binds throughout — the node shape offers 1.68 GiB per vCPU and the
workload wants 2 — so every node count below is driven by memory.

### Cost per month

| | Requests | Autopilot | Standard, best case |
| --- | --- | --- | --- |
| Production | 20 vCPU / 40 GiB | **$866** | **$717** (4 nodes) |
| Staging | 8 vCPU / 16 GiB | **$390** | **$395** (2 nodes) |
| Dev | 4 vCPU / 8 GiB | **$232** | **$234** (1 node) |
| **Estate** | 32 vCPU / 64 GiB | **$1,488** | **$1,346** |

Standard's column assumes **perfect bin-packing** — every node filled to
its allocatable ceiling, no headroom, no spare capacity for upgrades.
That is the most favourable assumption available to it, and it is
deliberate: an argument for Autopilot that only holds against a badly run
Standard cluster is not an argument.

### Reading it

**Standard's floor is 10% cheaper across the estate** — and all of that
advantage is in production. Staging and dev land within $5 of Autopilot,
because at small scale a node is a chunky unit: dev needs 8 GiB and the
smallest sensible node hands it 13.3. Autopilot has no such granularity,
which is why small and short-lived clusters favour it. An idle Autopilot
cluster costs the $73 management fee and nothing more; a Standard cluster
cannot idle below one running node.

Two smaller effects, both excluded above: ephemeral storage adds under 1%
on Autopilot, and Autopilot enforces a minimum request of 250 mCPU /
512 MiB per Pod. The reference app sits exactly on that floor, so nothing
is rounded up — but a cluster of many very small Pods pays the floor
regardless, which makes Autopilot a poor fit for that shape of workload.

### The Standard column is a floor, not a forecast

No real cluster runs at its allocatable ceiling. A rolling update needs
room for surge Pods, HPA needs room to scale into, and a node upgrade
needs somewhere to drain to. Putting that back, across the estate:

| Standard estate | Nodes | Utilisation | Cost | vs Autopilot |
| --- | --- | --- | --- | --- |
| Perfect packing | 7 | 69% | $1,346 | 10% cheaper |
| 25% headroom, prod zone-balanced | 9 | 53% | $1,668 | 12% dearer |
| ...and prod survives losing a zone | 12 | 40% | $2,151 | 45% dearer |

**Parity is at 61% packing efficiency.** Above it Standard is cheaper on
compute; below it Autopilot is. That number is worth remembering because
it does not depend on the size of the estate: Autopilot costs $19.84 per
GiB of requests per month at this workload's CPU:memory ratio, a node
offers allocatable memory at $12.11 per GiB, and the ratio of the two is
61% at any scale. The entire decision lives inside that band — and where
a cluster sits in it is not a fact about GKE. It is a fact about how much
attention someone pays to bin-packing, every quarter, in every
environment.

The third row deserves the most attention. Pre-buying idle node capacity
to absorb a zone failure is what makes a regional Standard cluster
actually regional; skip it and a zone outage becomes a capacity outage.
Autopilot has no equivalent line item, because unused capacity is not
yours to pay for.

Committed-use discounts and Spot capacity cut both columns and roughly
preserve the ratio. They are not an argument for either mode.

### Where real clusters sit in that band

Below 61%, on the available evidence. Two different ratios both get
called "utilisation" and only one of them moves this decision:

- **Usage against requests.** Apps use roughly 8–10% of the CPU and
  20–23% of the memory they ask for. This is the widely cited number and
  it is **irrelevant here: Autopilot bills requests, not usage.**
  Over-requesting costs the same in both modes. It is a rightsizing
  problem, and it inflates both columns equally.
- **Requests against node capacity.** The bin-packing ratio, and the one
  that sets the parity point. Fleet reports put the memory gap between
  provisioned and requested at 57% in one generation and 79% in the next
  — packing efficiency somewhere between 20% and 45%.

Both sit well below 61%, which inverts the table above: at the packing
fleets actually average, Autopilot is roughly 30–65% cheaper than
Standard rather than dearer. The zone-resilient row (40%) lands in that
same band by an unrelated route.

Treat the exact percentages with suspicion. They come from vendors
selling the fix, and a CPU gap that moves from 40% to 69% in a year
suggests unstable methodology more than a real collapse. The direction is
consistent across all of them, and the direction is the load-bearing
part: nobody's average cluster is packed to 98%, and most are not packed
to 61%.

## Why Autopilot anyway

The premium exists only against a perfectly packed estate, where it is
**$142/month**. Add the headroom a real cluster needs and it disappears:
Autopilot comes out **$180/month cheaper**, and $663 cheaper again once
production is sized to survive a zone loss. What the premium buys, in the
one case where there is one:

### What one Kubernetes upgrade costs

Upgrades are not optional and not rare. Kubernetes ships a minor version
roughly every three months, and GKE gives each one **14 months of
standard support** — so staying supported means two to three upgrades a
year, per cluster, forever.

Start with what Autopilot does *not* save you, because the honest version
of this argument is smaller than the marketing one. **Node auto-upgrade
is enabled by default on Standard**, so the mechanics roll on their own
in both modes. These stay yours either way:

- reading the release notes and the removed-API list
- scanning workloads for deprecated API usage
- keeping PodDisruptionBudgets correct
- making applications survive eviction and rescheduling
- validating the estate after each rollout

What Standard adds on top is the **node rollout and its failure modes**.
A node pool upgrade drains nodes one at a time and can take *up to a few
hours* per pool. GKE honours PDBs and graceful termination for up to one
hour per node, then force-deletes the Pods anyway — so a conservative PDB
does not prevent disruption, it just converts a fast rollout into a slow
one that still ends in a forced eviction. Someone owns that, per pool,
per environment.

A model for one minor version across three environments. These are
estimates, not measurements — substitute your own and the shape holds:

| | Standard | Autopilot |
| --- | --- | --- |
| Review, scanning, validation (above) | 4–8 h | 4–8 h |
| Rollout planning: strategy, order, windows, PDB review | 1–2 h | — |
| Attending three node rollouts | 3–9 h | — |
| Failure tail: stuck drains, blocked PDBs, forced evictions — amortised over upgrades that go wrong | 1–3 h | — |
| **Total** | **9–22 h** | **4–8 h** |

Call the difference **5–14 hours per upgrade**, so **15–42 hours a year**
at three upgrades. At a loaded $75–100/hour that is **$95–350/month** —
the same order as the entire compute premium, and frequently larger.

**The resource cost, by contrast, is nothing.** Surge upgrades add one
node for the length of a rollout: a few node-hours, under a dollar. Even
a blue-green upgrade, which temporarily doubles a pool, costs ten dollars
or so per pass. The resources an upgrade genuinely needs are the standing
headroom that lets drained Pods land somewhere — and that is already
priced in the packing table above, not an extra line.

So the answer to "what does an upgrade cost" is: **almost no money and a
day or two of an engineer's attention, two or three times a year, per
estate.** Upgrades are also the *easiest* node-layer task to automate.
The ones that resist automation — capacity incidents, autoscaler tuning,
re-shaping pools as workloads change — sit on top of this figure.

### And the rest

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

Put together, the two quantified halves land in the same place. The
compute premium is $142/month against a perfect estate and negative
against a realistic one; the upgrade work alone is $95–350/month.
Standard wins on cost only where someone holds every cluster above 61%
packing efficiency *and* absorbs the rollout work for free — and if that
is genuinely cheaper for you, Standard is the correct choice and Socle is
the wrong tool. That is a real position, not a rhetorical one. It just is
not the position this project is built around.

## What you give up

- Dataplane V2 only. No Calico, no self-managed Cilium, no custom eBPF.
- No SSH to nodes, no host namespaces, no writable `hostPath`.
- No privileged Pods outside Google's [partner allowlists][partners] —
  check your observability vendor against that list before adopting.
- Container-Optimized OS only. No Ubuntu or Windows node pools.
- Automatic upgrades. You choose the maintenance window, not whether.

Socle's catalog is built to need none of these — that is a design
constraint on the catalog, not a claim verified against a running
cluster. The catalog does not exist yet at pre-0.1.0; when it lands, its
Autopilot compatibility is part of its own acceptance, and any component
that turns out to need node access is a problem for that component, not
grounds for reopening this decision.

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
- [Standard cluster upgrades][upgrades] and [GKE versioning and
  support][versioning] — surge and blue-green mechanics, PDB handling,
  the 14-month support window
- [GKE Dataplane V2][dpv2]
- [Autopilot partner workloads][partners]
- [Cast AI Kubernetes cost benchmark][castai-benchmark] and [resource
  optimization report][castai-report] — the utilisation figures. Vendor
  research; read the caveat above.

Rates were read in September 2026 for us-central1 and will drift. The
ratio between the two modes moves far less than the absolute numbers, and
the ratio is what this page is really about — but re-price before quoting
anything.

[pricing]: https://cloud.google.com/kubernetes-engine/pricing
[vm-pricing]: https://cloud.google.com/compute/vm-instance-pricing
[comparison]: https://cloud.google.com/kubernetes-engine/docs/resources/autopilot-standard-feature-comparison
[requests]: https://cloud.google.com/kubernetes-engine/docs/concepts/autopilot-resource-requests
[upgrades]: https://cloud.google.com/kubernetes-engine/docs/concepts/cluster-upgrades
[versioning]: https://cloud.google.com/kubernetes-engine/versioning
[dpv2]: https://cloud.google.com/kubernetes-engine/docs/concepts/dataplane-v2
[partners]: https://cloud.google.com/kubernetes-engine/docs/resources/autopilot-partners
[castai-benchmark]: https://cast.ai/reports/kubernetes-cost-benchmark/
[castai-report]: https://cast.ai/blog/2026-state-of-kubernetes-resource-optimization-cpu-at-8-memory-at-20-and-getting-worse/
