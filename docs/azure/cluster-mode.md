# AKS cluster mode: Automatic vs Standard + Node Auto-Provisioning

**AKS Standard + Node Auto-Provisioning.** NAP runs the same engine
Automatic would have preconfigured. The upgrade channel and policy
enforcement are this module's own hardcoded choice, not Microsoft's — see
[managed scope](managed-scope.md) — the same posture Automatic would force,
just decided in code instead of by the platform.

Need Windows node pools or an IPv6 cluster? NAP supports neither, on any
tier — Socle is not the right foundation for that cluster.

## What this bundles

- NAP provisions and scales workload nodes — the same open-source engine
  Automatic uses, opt-in and explicit here instead of preconfigured.
- No separate Azure charge for NAP itself: the retail price list carries a
  per-category compute meter only under the Automatic product — Standard
  has none. Node price is identical to running Karpenter self-hosted; NAP's
  advantage is skipping the operational cost of running that controller,
  not a lower bill.
- Upgrade channel and policy enforcement are hardcoded by this module, not
  a variable — the module's own choice, not Microsoft's. Maintenance-window
  timing is what's actually left to the factory to configure.
- NAP's own limits apply regardless of tier: no Windows node pools, no IPv6
  clusters.

## The two options

|  | Standard + NAP | Automatic |
| --- | --- | --- |
| Per-vCPU surcharge | None | +17.5% on On-Demand, +94.7% on Spot |
| Pod readiness SLA | None | 99.9% of qualifying operations in under 5 minutes |
| Upgrade channel, policy enforcement | Hardcoded by the module | Forced by the platform |
| System components | Factory-operated | Microsoft-operated, no access |

## Cost

- Reference estate: one prod environment 24/7, two UAT environments at 12h
  per working day. Two nodes per environment (one Standard_D4s_v5, one
  Standard_D8s_v5 — 12 vCPU / 48 GiB total), one cluster per environment.
- France Central list price, September 2026.

| Estate of three environments | Standard + NAP | Automatic |
| --- | --- | --- |
| Nodes (identical price either way) | $841.34 | $841.34 |
| Control plane | $219.00 | $350.40 |
| Per-vCPU surcharge | — | $147.25 |
| **Total per month** | **$1,060.34** | **$1,338.99** |

The surcharge is a fixed $/vCPU/h, not a percentage of what the node
actually costs — so it hits hardest exactly where compute is cheapest. On
On-Demand it's +17.5%. On Spot, the same fixed amount is **+94.7%**,
because the underlying VM price it's added to is so much lower.

## Why, beyond cost

Automatic's own tax doesn't scale down with Spot — it stays a fixed
$/vCPU/h, so on Spot it costs nearly as much as the compute itself.
Spot's own discount is untouched; the tax on top of it isn't. Against
that, and against a pod-readiness SLA, Automatic isn't worth its permanent
cost.

## What you give up

- The pod-readiness SLA (99.9% of qualifying operations in under 5
  minutes) — Automatic-only, financially backed.
- A platform-enforced upgrade channel and policy baseline: Automatic's
  `stable` channel and policy enforcement can't be changed by anyone, ever.
  Standard + NAP hardcodes the same values today, but as this module's own
  choice, not a guarantee Azure enforces.

## Sources

Read September 2026, France Central pricing.

[AKS Automatic overview][automatic] · [node auto-provisioning][nap] ·
[Azure Retail Prices API][retail-prices].

[automatic]: https://learn.microsoft.com/en-us/azure/aks/intro-aks-automatic
[nap]: https://learn.microsoft.com/en-us/azure/aks/node-auto-provisioning
[retail-prices]: https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices
