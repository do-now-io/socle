# GKE cluster mode: Autopilot vs Standard

**Autopilot only. There is no cluster mode option.** Mode is fixed at
creation; changing it later means a second cluster and a migration.

Need Standard — another CNI, node access, privileged Pods, another node OS?
Socle is not the right foundation for that cluster.

## The two options

|  | Autopilot | Standard |
| --- | --- | --- |
| Nodes | Google provisions and operates them | You own them |
| Billing | Pod resource requests | Node capacity, used or idle |
| Node upgrades, patching, repair | Google | Automated by default, supervised by you |
| CNI | Dataplane V2, enforced | Your choice |
| Node access | None | Full |
| Hardening defaults | Workload Identity, Shielded nodes, network policy on | Off unless enabled |

## Cost

Reference estate: prod 20 vCPU / 40 GiB of Pod requests, staging 8 / 16, dev
4 / 8. us-central1 list price, 730-hour month.

| Estate of three clusters | Per month |
| --- | --- |
| **Autopilot** | **$1,488** |
| Standard, packed to the allocatable ceiling | $1,346 |
| Standard, with the headroom rollouts and autoscaling need | $1,668 |
| Standard, production surviving a zone loss | $2,151 |

- Autopilot sits between a Standard estate nobody sustains and one sized the
  way production actually gets sized.
- The cluster fee applies to both modes and cancels out.

## Why, beyond cost

- **Upgrades.** Node auto-upgrade is on in both modes, so release notes and
  validation cost the same. Standard adds attending the node rollout: 5–14
  hours per minor version, 15–42 hours a year, for nothing a user can see.
- **One shape of cluster.** Two modes would double the surface the module
  covers and halve how well either half is tested.

## What you give up

- Dataplane V2 only — no Calico, no self-managed Cilium, no custom eBPF.
- No SSH to nodes, no host namespaces, no writable `hostPath`.
- No privileged Pods outside Google's [partner allowlists][partners].
- Container-Optimized OS only.
- Automatic upgrades — you choose the window, not whether.
- A floor of 250 mCPU / 512 MiB billed per Pod.

The catalog is built to need none of these. That is a design constraint on the
catalog, not a fact verified against a running cluster.

## Sources

Read September 2026. Autopilot rates are not published per region, so these
are us-central1; re-price before quoting.

[GKE pricing][pricing] · [Autopilot and Standard comparison][comparison] ·
[cluster upgrades][upgrades] · [versioning and support][versioning] ·
[Autopilot resource requests][requests] · [Dataplane V2][dpv2] ·
[partner workloads][partners].

[pricing]: https://cloud.google.com/kubernetes-engine/pricing
[comparison]: https://cloud.google.com/kubernetes-engine/docs/resources/autopilot-standard-feature-comparison
[upgrades]: https://cloud.google.com/kubernetes-engine/docs/concepts/cluster-upgrades
[versioning]: https://cloud.google.com/kubernetes-engine/versioning
[requests]: https://cloud.google.com/kubernetes-engine/docs/concepts/autopilot-resource-requests
[dpv2]: https://cloud.google.com/kubernetes-engine/docs/concepts/dataplane-v2
[partners]: https://cloud.google.com/kubernetes-engine/docs/resources/autopilot-partners
