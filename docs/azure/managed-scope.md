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
| Policy enforcement | Azure Policy + baseline Pod Security Standards, Enforce — the module's own choice |
| Backup | Velero, CSI-snapshot mode always; node-agent needs its namespace excluded |
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
| Policy | Deployment Safeguards, baseline Pod Security Standards | Enforce mode — the module turns this on |

**Decision.** Storage CSI stays AKS-managed; monitoring is turned on
explicitly; Deployment Safeguards is turned on at Baseline/Enforce — what
Automatic would have forced, chosen here instead of inherited.

- Disk and File CSI have no cross-cloud equivalent worth keeping uniform —
  same logic as any provider-native component with nothing to replace it
  with.
- Standard doesn't default to any monitoring pipeline — only a portal-only
  dashboard with nothing behind it. Managed Prometheus and Container
  Insights need an explicit `az aks` flag or Terraform block either way, so
  this module sets them.
- Deployment Safeguards is Microsoft's own documented best-practice
  collection, not an Automatic-only convenience: resource requests and
  limits set where missing, anti-affinity and topology spread added,
  `:latest` image tags rejected, in-tree storage classes rejected in favor
  of the CSI drivers already decided above. Standard just doesn't turn it
  on by itself.

## Backup

**Decision: Velero, CSI-snapshot mode by default.**

- Baseline Pod Security Standards forbid privileged containers and
  `hostPath` volumes — both required by Velero's node-agent, the mode
  that produces a portable, file-level backup restorable outside the
  account and region it was taken in. Blocked, by this module's own
  choice above.
- Namespaces can be excluded from Deployment Safeguards and Pod Security
  Standards entirely (`az aks safeguards update --excluded-ns`) — a
  workload in an excluded namespace is left alone by the baseline
  standards. Giving Velero's own namespace that exclusion recovers the
  node-agent mode; it isn't excluded by default here, since this module
  doesn't deploy Velero — that exclusion is set when whatever does deploy
  it, through the socle artifact, needs it.
- CSI-snapshot mode needs neither privileged access nor `hostPath`, and
  covers cluster objects plus volume snapshots regardless.

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

## Customer-managed keys

**Decision: refused, for two different reasons — neither is cost-free to
reverse.**

- Kubernetes Secrets (etcd): Microsoft already encrypts etcd at rest with
  its own key, unconditionally — nothing insecure by default. The
  customer-key layer on top (AKS's KMS etcd encryption via Key Vault)
  doesn't fit this module's identity model: it requires a user-assigned
  identity created and granted Key Vault access *before* the cluster
  exists, not the `SystemAssigned` identity this module uses — a circular
  dependency Microsoft's own docs call out. Not a cost problem, an
  architecture one.
- Logs (Log Analytics / Container Insights): also Microsoft-encrypted by
  default. A customer key here requires a dedicated cluster resource,
  billed on a commitment-tier model with a 100 GB/day floor — real,
  fixed money committed regardless of what a given client's cluster
  actually logs.
- Both are the client's own compliance decision to make on their own Key
  Vault, the same class of call as the disk encryption set above
  (AZU-0067) — not something to default into an empty-shell,
  multi-client module.

## Module specification

| Variable | Default | Constraint |
| --- | --- | --- |
| `maintenance_window` | none — required | ≥ 4 hours, staggered per cluster |
| `node_os_maintenance_window` | none — required | Same constraint, separate schedule |
| `deployment_safeguards_excluded_namespaces` | `[]` | Set by whichever layer deploys a workload that needs the exclusion — not defaulted here |

Hardcoded, no variable: the `stable` auto-upgrade channel, the
`KubernetesOfficial` support plan, and Deployment Safeguards at
Baseline/Enforce — Premium/LTS is never reachable through this module,
and neither is a weaker policy posture than the one Automatic would have
forced.

## Sources

Read September 2026.

[Automatic upgrade behavior](https://learn.microsoft.com/en-us/azure/aks/auto-upgrade-cluster) ·
[planned maintenance](https://learn.microsoft.com/en-us/azure/aks/planned-maintenance) ·
[long-term support](https://learn.microsoft.com/en-us/azure/aks/long-term-support) ·
[CSI storage drivers](https://learn.microsoft.com/en-us/azure/aks/csi-storage-drivers) ·
[deployment safeguards](https://learn.microsoft.com/en-us/azure/aks/deployment-safeguards) ·
[KMS etcd encryption](https://learn.microsoft.com/en-us/azure/aks/use-kms-etcd-encryption) ·
[Log Analytics customer-managed keys](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/customer-managed-keys) ·
[Velero node-agent configuration](https://velero.io/docs/main/supported-configmaps/node-agent-configmap/) ·
[Kubernetes Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards) ·
[crossplane-contrib/provider-azure](https://github.com/crossplane-contrib/provider-azure) ·
[crossplane-contrib/provider-upjet-azure](https://github.com/crossplane-contrib/provider-upjet-azure).
