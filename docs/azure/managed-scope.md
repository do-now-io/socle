# AKS managed scope: upgrades, add-ons, identity

Who operates what on an Automatic cluster — see
[cluster mode](cluster-mode.md).

| Question | Position |
| --- | --- |
| Kubernetes minor version | AKS's stable channel decides — locked, no override |
| Which cluster upgrades first | Ours, through the maintenance window |
| Long-Term Support (Premium) | Refused — the stable channel never lets a cluster sit still long enough to need it |
| Storage CSI (Disk, File) | AKS-managed, no in-tree alternative available |
| Monitoring | Managed Prometheus + Container Insights, Automatic's own default |
| Policy enforcement | Automatic's own baseline Pod Security Standards, enforce mode, locked |
| Backup | Velero, CSI-snapshot mode by default; the node-agent mode needs an explicit namespace exclusion |
| Workload identity | Microsoft Entra Workload ID — preconfigured, not optional |

## Upgrades

| Channel | Behavior |
| --- | --- |
| `none` | No autoupgrade, stays on the version it was created with |
| `patch` | Latest patch, same minor version |
| `stable` | Latest patch on minor N-1 |
| `rapid` | Latest patch on the newest minor |

**Decision: the stable channel, because there is no other option — and the
ring order comes from the maintenance window, not from a channel choice.**

- Automatic clusters can't change the autoupgrade channel at all: it's
  preconfigured to stable, and nothing in the tier or support-plan
  documentation describes a way to override it.
- Two clocks, one owner each: Kargo owns the socle artifact, AKS owns the
  Kubernetes version.
- What stays ours: three maintenance-window configurations can run at once —
  `default` (AKS's own weekly platform releases), `aksManagedAutoUpgradeSchedule`
  (the minor-version bump), `aksManagedNodeOSUpgradeSchedule` (node OS
  patching). Staggering `aksManagedAutoUpgradeSchedule` per cluster is the
  ring order: dev first, staging next, prod last.
- Two real constraints on that plan: maintenance windows are best-effort —
  AKS can break one for an urgent or critical patch regardless of what's
  configured — and reusing one maintenance configuration across several
  clusters in the same subscription risks ARM throttling errors on the
  upgrade calls themselves. Every cluster needs its own window either way.

### Long-Term Support

**Decision: refused.** Not because Premium tier blocks it — it doesn't — but
because it can't do anything for a cluster on this module. LTS buys time on
an aging Kubernetes version; the stable channel, locked regardless of tier,
never lets a cluster become one. Paying for Premium's LTS support plan here
would extend a support window the cluster is never in a position to need.

## Add-ons: who manages what

| Component | Position | Notes |
| --- | --- | --- |
| Azure Disk CSI | AKS-managed | Default since Kubernetes 1.21, no in-tree alternative since 1.26 |
| Azure File CSI | AKS-managed | Same lifecycle as Disk CSI |
| Metrics and dashboards | Managed Prometheus + Container Insights | Automatic's own default, not locked |
| Policy | Azure Policy + baseline Pod Security Standards | Locked by Automatic, enforce mode — nothing for the catalog to add here, and nothing it should contradict |

**Decision.** Storage CSI stays AKS-managed; monitoring stays on Automatic's
own default; policy is inherited as given, not layered on top of.

- Disk and File CSI have no cross-cloud equivalent worth keeping uniform —
  same logic as any provider-native component with nothing to replace it
  with.
- The baseline Pod Security Standards enforced here are already the
  strictest thing a workload will meet on this cluster. Anything the
  catalog would add on top is redundant at best.

## Backup

**Decision: Velero, CSI-snapshot mode by default.**

- The enforced baseline Pod Security Standards forbid privileged containers
  and `hostPath` volumes — both required by Velero's node-agent, the mode
  that produces a portable, file-level backup restorable outside the
  account and region it was taken in. Blocked by default.
- Unlike the rest of Automatic's locked posture, this one has a documented
  way out: a namespace can be excluded from deployment safeguards
  (`az aks safeguards update --excluded-ns`), and a workload in an excluded
  namespace is left alone by the baseline standards entirely. Giving
  Velero's own namespace that exclusion recovers the node-agent mode — a
  decision for whoever deploys Velero through the socle artifact, not a
  default this module sets.
- CSI-snapshot mode needs neither privileged access nor `hostPath`, and
  covers cluster objects plus volume snapshots either way.

## Identity

Automatic preconfigures Microsoft Entra Workload ID; it isn't a toggle.

**Decision: workloads that need Azure access get a federated Entra identity
bound to their Kubernetes service account.** That is all the shell needs
today.

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
| `k8s_support_plan` | `"KubernetesOfficial"` | Premium/LTS not exposed as an option |
| `deployment_safeguards_excluded_namespaces` | `[]` | Set by whichever layer deploys a workload that needs the exclusion — not defaulted here |

Absent by decision: any auto-upgrade channel toggle, the Premium tier, any
Pod Security Standards level toggle.

## Sources

Read September 2026.

[Automatic upgrade behavior][auto-upgrade] · [planned maintenance][maintenance] ·
[long-term support][lts] · [CSI storage drivers][csi] ·
[deployment safeguards][safeguards] · [Velero node-agent configuration][velero-node-agent] ·
[Kubernetes Pod Security Standards][pss] ·
[crossplane-contrib/provider-azure][cp-azure-old] ·
[crossplane-contrib/provider-upjet-azure][cp-azure-new].

[auto-upgrade]: https://learn.microsoft.com/en-us/azure/aks/auto-upgrade-cluster
[maintenance]: https://learn.microsoft.com/en-us/azure/aks/planned-maintenance
[lts]: https://learn.microsoft.com/en-us/azure/aks/long-term-support
[csi]: https://learn.microsoft.com/en-us/azure/aks/csi-storage-drivers
[safeguards]: https://learn.microsoft.com/en-us/azure/aks/deployment-safeguards
[velero-node-agent]: https://velero.io/docs/main/supported-configmaps/node-agent-configmap/
[pss]: https://kubernetes.io/docs/concepts/security/pod-security-standards
[cp-azure-old]: https://github.com/crossplane-contrib/provider-azure
[cp-azure-new]: https://github.com/crossplane-contrib/provider-upjet-azure
