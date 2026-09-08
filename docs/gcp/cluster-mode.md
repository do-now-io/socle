# GKE cluster mode: Autopilot vs Standard

**Socle provisions Autopilot clusters. There is no cluster mode option.**

If you need Standard — a CNI other than Dataplane V2, node-level access,
privileged Pods, a node OS other than Container-Optimized OS — Socle is not
the right foundation for that cluster.

Mode is fixed at creation. Changing it later means building a second cluster
and migrating to it.

## The two options

|  | Autopilot | Standard |
| --- | --- | --- |
| Nodes | Google provisions and operates them | You own them |
| Billing | Pod resource requests | Node capacity, used or idle |
| Node upgrades, patching, repair | Google | Automated by default, supervised by you |
| CNI | Dataplane V2, enforced | Your choice |
| Node access | None | Full |
| Hardening defaults | Workload Identity, Shielded nodes, network policy all on | Off unless you enable them |

## Why

**It costs about the same.** Reference estate: prod 20 vCPU / 40 GiB of Pod
requests, staging 8 / 16, dev 4 / 8. Priced in us-central1 at list price,
730-hour month, September 2026.

| Estate of three clusters | Per month |
| --- | --- |
| **Autopilot** | **$1,488** |
| Standard, packed to the allocatable ceiling | $1,346 |
| Standard, with the headroom rollouts and autoscaling need | $1,668 |
| Standard, production able to survive a zone loss | $2,151 |

Autopilot lands between a Standard estate packed to a level nobody sustains
and one sized the way production actually gets sized. The $0.10/hour cluster
fee applies to both modes and cancels out.

**Upgrades are not free on Standard.** Node auto-upgrade is on by default in
both modes, so reading release notes and validating afterwards costs the same
either way. What Standard adds is attending the node rollout: a pool drains
one node at a time, PodDisruptionBudgets are honoured for an hour per node and
then overridden, and someone watches that per environment. Call it 5–14 hours
per minor version, 15–42 hours a year — the same order as the entire cost
difference above, and it buys nothing a user can see.

**One shape of cluster.** Supporting both modes would double the surface the
module covers and halve how well either half is tested.

## What you give up

- Dataplane V2 only. No Calico, no self-managed Cilium, no custom eBPF.
- No SSH to nodes, no host namespaces, no writable `hostPath`.
- No privileged Pods outside Google's [partner allowlists][partners].
- Container-Optimized OS only. No Ubuntu or Windows node pools.
- Automatic upgrades. You choose the window, not whether.
- A floor of 250 mCPU / 512 MiB billed per Pod.

Socle's catalog is built to need none of these — a design constraint on the
catalog, not a fact verified against a running cluster.

## Sources

Read September 2026. Rates are us-central1 because region-specific Autopilot
rates are not published in machine-readable form; re-price before quoting.

[GKE pricing][pricing] · [Autopilot and Standard comparison][comparison] ·
[Standard cluster upgrades][upgrades] · [versioning and support][versioning] ·
[Autopilot resource requests][requests] · [Dataplane V2][dpv2] ·
[Autopilot partner workloads][partners].

[pricing]: https://cloud.google.com/kubernetes-engine/pricing
[comparison]: https://cloud.google.com/kubernetes-engine/docs/resources/autopilot-standard-feature-comparison
[upgrades]: https://cloud.google.com/kubernetes-engine/docs/concepts/cluster-upgrades
[versioning]: https://cloud.google.com/kubernetes-engine/versioning
[requests]: https://cloud.google.com/kubernetes-engine/docs/concepts/autopilot-resource-requests
[dpv2]: https://cloud.google.com/kubernetes-engine/docs/concepts/dataplane-v2
[partners]: https://cloud.google.com/kubernetes-engine/docs/resources/autopilot-partners
