# AKS managed scope: upgrades, add-ons, identity

Who operates what on a Standard + NAP cluster — see
[cluster mode](cluster-mode.md).

| Question | Position |
| --- | --- |
| Kubernetes minor version | The `stable` channel — our own choice, not imposed |
| Which cluster upgrades first | Ours, through the maintenance window |
| Long-Term Support (Premium) | Refused — `stable` never lets a cluster sit still long enough to need it |
| Storage CSI (Disk, File) | AKS-managed, no in-tree alternative available |
| Monitoring | Managed Prometheus + Container Insights, enabled explicitly |
| Policy enforcement | Not this module's job |
| Backup | Velero, both modes available |
| Workload identity | Microsoft Entra Workload ID, enabled explicitly |

## Upgrades

| Channel | Behavior |
| --- | --- |
| `none` | No autoupgrade, stays on the version it was created with |
| `patch` | Latest patch, same minor version |
| `stable` | Latest patch on minor N-1 |
| `rapid` | Latest patch on the newest minor |

**Decision: the `stable` channel, hardcoded — and the ring order comes from
the maintenance window, not from the channel.**

- AKS keeps clusters in a rolling N-2 support window. `stable` sits one
  minor behind latest, the same margin a client never has to think about
  falling out of support on.
- Two clocks, one owner each: Kargo owns the socle artifact, AKS owns the
  Kubernetes version.
- Rings come from the maintenance window, not the channel: three
  configurations can run at once — `default` (AKS's own weekly platform
  releases), `aksManagedAutoUpgradeSchedule` (the minor-version bump),
  `aksManagedNodeOSUpgradeSchedule` (node OS patching). Staggering
  `aksManagedAutoUpgradeSchedule` per cluster is the ring order: dev first,
  staging next, prod last.
- Two real constraints on that plan: maintenance windows are best-effort —
  AKS can break one for an urgent or critical patch regardless of what's
  configured — and reusing one maintenance configuration across several
  clusters in the same subscription risks ARM throttling errors on the
  upgrade calls themselves. Every cluster needs its own window either way.

### Long-Term Support

**Decision: refused.** LTS buys time on an aging Kubernetes version. A
cluster hardcoded to the `stable` channel is never in that position — it's
always within one minor of latest. Paying for Premium's LTS support plan
would extend a support window this module never lets a cluster need.

## Add-ons: who manages what

| Component | Position | Notes |
| --- | --- | --- |
| Azure Disk CSI | AKS-managed | Default since Kubernetes 1.21, no in-tree alternative since 1.26 |
| Azure File CSI | AKS-managed | Same lifecycle as Disk CSI |
| Metrics and dashboards | Managed Prometheus + Container Insights | Not on by default on Standard — this module turns both on |
| Policy | Azure Policy, Pod Security Standards | Neither enabled here — see below |

**Decision.** Storage CSI stays AKS-managed; monitoring is turned on
explicitly; policy enforcement is left out of this module entirely.

- Disk and File CSI have no cross-cloud equivalent worth keeping uniform —
  same logic as any provider-native component with nothing to replace it
  with.
- Standard doesn't default to any monitoring pipeline — only a portal-only
  dashboard with nothing behind it. Managed Prometheus and Container
  Insights need an explicit `az aks` flag or Terraform block either way, so
  this module sets them.
- Policy enforcement is an application-facing concern, the same boundary
  that keeps Velero out of this module (see Backup) — it arrives through
  whatever deploys workloads, not through the cluster's own creation.

## Backup

**Decision: Velero, both modes available.**

- This module enables no Pod Security Standards level and no Azure Policy
  baseline. Without either, nothing here forbids privileged containers or
  `hostPath` volumes — Velero's node-agent, the mode that produces a
  portable, file-level backup restorable outside the account and region it
  was taken in, runs the same as the CSI-snapshot mode.
- If a later layer turns on baseline Pod Security Standards for its own
  reasons, Velero's namespace needs an explicit exclusion
  (`az aks safeguards update --excluded-ns`) to keep the node-agent working
  — a consequence for whoever makes that call, not a default this module
  sets.

## Identity

Standard doesn't preconfigure Microsoft Entra Workload ID — this module
turns it on explicitly: the OIDC issuer, and workload identity federation
for anything that needs Azure access.

**Decision: workloads that need Azure access get a federated Entra
identity bound to their Kubernetes service account.** That is all the
shell needs today.

### Crossplane's Azure provider

The community-maintained native provider was archived in May 2025. The
actively developed line is the Upjet-generated `provider-family-azure` and
its underlying `provider-upjet-azure` — regular releases, low open-issue
count relative to its size, most recent push days before this was written.
Not abandoned, not a blocker for the identity this shell exposes.

## Module specification

| Variable | Default | Constraint |
| --- | --- | --- |
| `maintenance_window` | none — required | ≥ 4 hours, staggered per cluster |
| `node_os_maintenance_window` | none — required | Same constraint, separate schedule |

Hardcoded, no variable: the `stable` auto-upgrade channel, and the
`KubernetesOfficial` support plan — Premium/LTS is never reachable through
this module, the same way extended support is refused outright elsewhere.
Absent by decision: any Pod Security Standards or Azure Policy toggle —
left to whatever layer deploys workloads.

## Sources

Read September 2026.

[Automatic upgrade behavior](https://learn.microsoft.com/en-us/azure/aks/auto-upgrade-cluster) ·
[planned maintenance](https://learn.microsoft.com/en-us/azure/aks/planned-maintenance) ·
[long-term support](https://learn.microsoft.com/en-us/azure/aks/long-term-support) ·
[CSI storage drivers](https://learn.microsoft.com/en-us/azure/aks/csi-storage-drivers) ·
[Velero node-agent configuration](https://velero.io/docs/main/supported-configmaps/node-agent-configmap/) ·
[crossplane-contrib/provider-azure](https://github.com/crossplane-contrib/provider-azure) ·
[crossplane-contrib/provider-upjet-azure](https://github.com/crossplane-contrib/provider-upjet-azure).
