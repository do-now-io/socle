# AKS cluster mode: Automatic vs Standard + Node Auto-Provisioning

**AKS Automatic.** Node provisioning, cluster and node-image upgrades, and
baseline security posture are handled by the platform; the factory does not
operate them.

Need Windows node pools, an IPv6 cluster, a pinned upgrade cadence, or policy
in warning-only mode? Socle is not the right foundation for that cluster.

## What Automatic actually bundles

- Locked: the system node pool — hosted outside the subscription, no
  `exec`/debug/SSH, no create/update/delete on its resources.
- Locked: node auto-provisioning (NAP) for every workload node — the same
  open-source engine Standard uses when NAP is turned on there, preconfigured
  here instead of opt-in.
- Locked: cluster auto-upgrade on the stable channel, one minor version
  behind the latest supported (N-1); node OS images upgrade the same way.
- Locked: Azure Policy deployment safeguards and baseline Pod Security
  Standards, in enforce mode — not warning.
- Locked: Azure RBAC for Kubernetes authorization, workload identity, the
  OIDC issuer, image cleaner, API server VNet integration.
- Default, not locked: Azure CNI Overlay powered by Cilium as the VNet's
  dataplane.
- Not available at all: Windows node pools, IPv6 clusters — NAP provisions
  every node here, and NAP supports neither.

## The two options

|  | Automatic | Standard + NAP |
| --- | --- | --- |
| Node provisioning | NAP, preconfigured | NAP, opt-in — same engine |
| System components (CoreDNS, etc.) | Hosted by Microsoft, outside the subscription, no access | Hosted and operated by the factory |
| VNet dataplane | Azure CNI Overlay + Cilium, the default | Kubenet is Standard's own default — Cilium is a choice the factory makes |
| Cluster upgrade | Forced, stable channel, N-1 | Manual, or a channel the factory picks |
| Node OS image upgrade | Forced | Manual, or a channel the factory picks |
| Policy enforcement | Azure Policy + Pod Security Standards, enforce mode, forced | Optional — enforce or warning, factory's choice |
| Pod readiness SLA | 99.9% of qualifying operations complete in under 5 minutes, financially backed | None |
| Control plane SLA | 99.95% with availability zones / 99.9% without | Same, on the Standard tier |
| Workload identity, OIDC issuer, image cleaner | Preconfigured | Optional, the factory wires them |
| Windows node pools, IPv6 | Not available | Available, without NAP |

## Cost

- Reference estate: one prod environment 24/7, two UAT environments at 12h
  per working day. Two nodes per environment (one Standard_D4s_v5, one
  Standard_D8s_v5 — 12 vCPU / 48 GiB total), one cluster per environment.
- France Central list price, September 2026. 730-hour month; a UAT
  environment is 261 hours (12h × ~21.75 working days).

| Meter | Rate |
| --- | --- |
| Node Standard_D4s_v5 (4 vCPU / 16 GiB) | $0.224/h |
| Node Standard_D8s_v5 (8 vCPU / 32 GiB) | $0.448/h |
| Control plane, Standard tier | $0.10/h per cluster |
| Control plane, Automatic | $0.16/h per cluster |
| Automatic surcharge, General Purpose class | $0.009801/vCPU/h |

| Estate of three environments | Standard + NAP | Automatic |
| --- | --- | --- |
| Nodes (identical price either way) | $841.34 | $841.34 |
| Control plane (3 clusters × 730h) | $219.00 | $350.40 |
| Per-vCPU surcharge | — | $147.25 |
| **Total per month** | **$1,060.34** | **$1,338.99** |

- The control plane delta is flat per cluster — $0.06/h more than Standard,
  regardless of node count. It shrinks in relative terms as a fleet grows.
- The per-vCPU surcharge does not: it is a fixed +17.5% on every vCPU-hour of
  compute (General Purpose class; $0.009801 ÷ $0.056 of the node's own
  per-vCPU rate), for as long as the cluster runs. It does not amortize.
- Node price itself is identical in both modes.

## Why, beyond cost

- **CNI.** Azure CNI Overlay powered by Cilium is Automatic's own default
  dataplane. There is no incompatible network stack to route around.
- **What's actually locked.** Only the system node pool is inaccessible.
  Workload nodes — where everything the catalog runs — keep normal AKS node
  behavior: OS choice, SSH, the usual access.
- **Day-2 load.** Cluster upgrades, node image patching, and the policy
  baseline run without a factory pipeline tracking every new AKS release.
- **Long-term support stays reachable.** Enabling LTS is a tier change
  (`az aks update --tier premium --k8s-support-plan AKSLongTermSupport`),
  documented as a configuration-only operation independent of cluster SKU —
  nothing in Microsoft's tier or LTS documentation restricts it to Base-SKU
  clusters. An Automatic cluster reaches Premium/LTS the same way a Standard
  one does.

## What you give up

- A pinned Kubernetes or node-image version: upgrades follow the stable
  channel automatically, on Microsoft's calendar, not a version the factory
  chose and validated first.
- Policy posture flexibility: Azure Policy and Pod Security Standards run in
  enforce mode, with no warning-only step to roll out a stricter policy
  gradually.
- Visibility into the system node pool: no logs beyond what AKS surfaces, no
  exec, no debug.
- Windows node pools and IPv6 clusters, as long as every node goes through
  NAP.
- A surcharge that never amortizes: +17.5% on every vCPU-hour, permanently,
  not a fee that shrinks in relative terms as the estate grows.

## Sources

Read September 2026, France Central pricing.

[AKS Automatic overview][automatic] · [managed system node pools][system-pools] ·
[node auto-provisioning][nap] · [pricing tiers][tiers] ·
[long-term support][lts] · [Azure Retail Prices API][retail-prices].

[automatic]: https://learn.microsoft.com/en-us/azure/aks/intro-aks-automatic
[system-pools]: https://learn.microsoft.com/en-us/azure/aks/automatic/aks-automatic-managed-system-node-pools-about
[nap]: https://learn.microsoft.com/en-us/azure/aks/node-auto-provisioning
[tiers]: https://learn.microsoft.com/en-us/azure/aks/free-standard-pricing-tiers
[lts]: https://learn.microsoft.com/en-us/azure/aks/long-term-support
[retail-prices]: https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices
