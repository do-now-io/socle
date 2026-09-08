# GKE cluster mode: Autopilot vs Standard

## The two options

|  | Autopilot | Standard |
| --- | --- | --- |
| Nodes | Google provisions and operates them | You own them |
| Billing | Pod resource requests | Node capacity, used or idle |
| Node upgrades, patching, repair | Google | Automated by default, supervised by you |
| CNI | Dataplane V2, enforced | Your choice |
| Node access | None | Full |
| Hardening defaults | Workload Identity, Shielded nodes, network policy all on | Off unless you enable them |

Mode is fixed when the cluster is created. Changing it later means
building a second cluster and migrating to it.

## What Socle does

**Socle provisions Autopilot clusters. There is no cluster mode option.**

If you need Standard — a CNI other than Dataplane V2, node-level access,
privileged Pods, a node OS other than Container-Optimized OS — Socle is
not the right foundation for that cluster, and the module will not
pretend otherwise.

## Why

### It costs about the same

```
Reference estate  prod 20 vCPU / 40 GiB of Pod requests, staging 8 / 16, dev 4 / 8
Priced            us-central1 list price, September 2026, 730-hour month
Standard nodes    e2 custom, 8 vCPU / 16 GiB, $161/month, 13.3 GiB allocatable
```

| Estate of three clusters | Per month |
| --- | --- |
| **Autopilot** | **$1,488** |
| Standard, packed to the allocatable ceiling | $1,346 |
| Standard, with the headroom rollouts and autoscaling need | $1,668 |
| Standard, production able to survive a zone loss | $2,151 |

Autopilot lands between a Standard estate packed to a level nobody
sustains and one sized the way production actually gets sized. The gap
either way is a couple of hundred dollars a month, before anyone's time
is counted. Two details worth knowing: the $0.10/hour cluster management
fee applies to both modes and cancels out, and an idle Autopilot cluster
costs that fee alone, where a Standard cluster cannot idle below one
running node.

Rates are us-central1 because region-specific Autopilot rates are not
published in a machine-readable form. Re-price before quoting.

### The upgrades are not free on Standard

Kubernetes ships a minor version roughly every three months and GKE gives
each one 14 months of standard support, so two to three upgrades a year
is the floor — per cluster, indefinitely.

Autopilot does not save you all of that, and the honest version of this
argument is smaller than it first looks. **Node auto-upgrade is on by
default on Standard**, so the rollout runs itself in both modes, and
reading release notes, scanning for removed APIs, keeping
PodDisruptionBudgets correct and validating afterwards cost the same
either way.

What Standard adds is the node rollout and its failure modes: a pool
drains one node at a time and can take hours, PDBs are honoured for an
hour per node and then overridden by force-deletion, and someone attends
that per environment. Call it 5–14 hours per minor version, so 15–42
hours a year. At a loaded rate that is $95–350/month — the same order as
the entire cost difference above, and it buys nothing a user can see.

The resources an upgrade consumes are negligible either way: a surge node
for the length of a rollout costs under a dollar. This is time, not
money.

### One shape of cluster

Socle ships one GCP foundation and tests it one way. Supporting both
modes would double the surface the module has to cover and halve how well
either half is tested.

## What you give up

- Dataplane V2 only. No Calico, no self-managed Cilium, no custom eBPF.
- No SSH to nodes, no host namespaces, no writable `hostPath`.
- No privileged Pods outside Google's [partner allowlists][partners] —
  check your observability vendor against that list before adopting.
- Container-Optimized OS only. No Ubuntu or Windows node pools.
- Automatic upgrades. You choose the maintenance window, not whether.
- A minimum of 250 mCPU / 512 MiB billed per Pod, so a workload made of
  many very small Pods pays the floor rather than what it asked for.

Socle's catalog is built to need none of these. That is a design
constraint on the catalog, not a fact verified against a running cluster
— the catalog does not exist yet at pre-0.1.0, and its Autopilot
compatibility is part of its own acceptance.

## Sources

- [GKE pricing][pricing] — Pod rates, cluster management fee
- [Autopilot and Standard feature comparison][comparison]
- [Standard cluster upgrades][upgrades] and [GKE versioning and
  support][versioning]
- [Autopilot resource requests][requests] — the per-Pod minimums
- [GKE Dataplane V2][dpv2] · [Autopilot partner workloads][partners]

[pricing]: https://cloud.google.com/kubernetes-engine/pricing
[comparison]: https://cloud.google.com/kubernetes-engine/docs/resources/autopilot-standard-feature-comparison
[upgrades]: https://cloud.google.com/kubernetes-engine/docs/concepts/cluster-upgrades
[versioning]: https://cloud.google.com/kubernetes-engine/versioning
[requests]: https://cloud.google.com/kubernetes-engine/docs/concepts/autopilot-resource-requests
[dpv2]: https://cloud.google.com/kubernetes-engine/docs/concepts/dataplane-v2
[partners]: https://cloud.google.com/kubernetes-engine/docs/resources/autopilot-partners
