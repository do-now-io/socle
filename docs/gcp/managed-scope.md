# GKE managed scope: upgrades, add-ons, identity

Which parts of a GKE cluster we let Google operate, and which we operate
ourselves. This document assumes Autopilot, which is the only mode Socle
provisions — see [cluster mode](README.md).

**The arbitration rule.** Do Now bills a flat fee plus a percentage of the
cloud bill, never per operation. So work the provider does reliably for a
reasonable surcharge is a candidate for **delegation to the cloud**, and work
that industrialises to a marginal cost of about zero is **taken on by the
factory**. Every position below states which side it lands on, and what it
costs to be wrong.

## Positions

| Question | Position | How the module expresses it |
| --- | --- | --- |
| Kubernetes minor version | **Delegated** — Google's release channel decides | `release_channel`, default `REGULAR` |
| Which cluster upgrades first | **Factory** — maintenance-window skew per environment | `maintenance_window`, required |
| Blocking an upgrade | **Factory**, exceptionally | `maintenance_exclusions`, default empty |
| Extended channel (24-month support) | **Refused** — impossible on Autopilot | absent |
| GKE system metrics and logs | **Delegated** — free, and not disableable | `logging_components`, `monitoring_components` |
| Control plane / kube-state metrics | **Catalog option** — billed per sample | in `monitoring_components`, off by default |
| GKE Auto-Monitoring | **Refused as a default** — silent per-sample cost | absent |
| Workload metrics collection | **Delegated to GMP** below ~850 samples/s per cluster | managed collection on, catalog owns what is scraped |
| Volume and config backup | **Factory** — Velero, homogeneous on four clouds | `backup_agent_enabled`, default `false` |
| Backup for GKE | **Catalog option** — $9 per namespace-month | same variable, opt-in |
| Config Connector | **Refused** — Crossplane confirmed | absent |
| Workload Identity Federation | **Delegated** — pre-configured, not optional | no variable, outputs only |
| The Crossplane provider's identity | **Factory** — module creates it | `crossplane_*` variables and outputs |

## 1. Upgrades

### What Google actually commits to

| Channel | Minor version arrives | Becomes an auto-upgrade target | Notes |
| --- | --- | --- | --- |
| Rapid | 1–2 weeks after upstream GA | 1–2 months later | **Excluded from the GKE SLA** |
| Regular (default) | ~2 months after Rapid | ~3 months later | Google's own recommendation |
| Stable | 3–4 months after Regular | ~2 months later | Changes land here last |
| Extended | aligned with Regular | aligned with Regular | **Cannot be used with Autopilot** |

Kubernetes ships three minor versions a year. Each gets about **14 months of
standard support** from the moment it reaches Regular, and the Extended channel
would stretch that to 24 — except that Google's own limitation list is
explicit: you cannot enrol a cluster in the Extended channel if it uses
*Autopilot cluster mode*. The pricing question is therefore moot, but worth
recording for the multi-cloud synthesis: extended support costs **$0.50 per
cluster per hour** on top of the $0.10 management fee once the minor version
passes end of standard support — $365 per cluster per month, which on the
reference estate would be **+$1,095 a month, or +74%**, to defer work we have
to do anyway. Google itself recommends against enrolling without a plan to move
on.

Autopilot clusters can only be enrolled in a channel; there is no unenrolled
mode to fall back to, and the deprecated "no channel" option disappears on
14 June 2027.

### Who decides the moment: channels or Kargo rings?

This is the question the ticket puts first, and the answer is that **there are
two clocks and each needs exactly one owner.**

The socle's clock is Kargo's: an OCI artifact version, promoted dev → staging →
prod, on our schedule. That is unchanged by anything here.

The Kubernetes minor version is Google's clock, and the levers we get are these:

- **The channel** decides *which* version and roughly *when* it becomes a
  target. Estate-wide, not per environment.
- **The maintenance window** decides *when in the week* a cluster may be
  touched. This is the only per-cluster ordering lever that costs nothing to
  maintain. A cluster whose window opens Tuesday takes a version before one
  whose window opens Saturday.
- **Maintenance exclusions** block upgrades over an explicit date range:
  `NO_UPGRADES` (90 days maximum, Google recommends under 30, three at most),
  `NO_MINOR_UPGRADES` and `NO_MINOR_OR_NODE_UPGRADES` (which may run to
  `UNTIL_END_OF_SUPPORT`). Twenty per cluster at most. They are dates, not
  recurrences, so a rolling exclusion is something the factory has to keep
  rewriting.
- **The floor.** `min_master_version` never lets the cluster sit below a
  version, and raising it forces an upgrade — the one lever that promotes on
  our command rather than Google's.
- **`disruption_budget`** sets a minimum interval between two control plane
  minor upgrades, and between two patch upgrades.
- **Pub/Sub notifications** (`UPGRADE_AVAILABLE_EVENT`, `UPGRADE_EVENT`,
  `SECURITY_BULLETIN_EVENT`, `UPGRADE_INFO_EVENT`) let the factory react rather
  than poll.

And one hard constraint that shapes all of it: a cluster must be left **at
least 48 hours of maintenance availability in any 92-day rolling window**,
counting only contiguous blocks of four hours or more. Exclusions are silently
deactivated when a version reaches end of standard support, upgraded, then
reactivated against the next version's deadline. You cannot outrun the
14-month clock; you can only choose where in it you sit.

**Recommendation.** One channel for the whole estate — `REGULAR` — and the ring
order expressed by *window skew inside the week*: dev Tuesday, staging
Wednesday, prod Saturday. It is declarative, it has no dates to roll forward,
it keeps every cluster of an estate on the same minor version, and it produces
a deterministic promotion order with three to four days of soak per hop. Rapid
is refused for anything a client depends on, because it is outside the SLA. The
`NO_MINOR_UPGRADES` exclusion is the brake the factory pulls when dev or
staging surfaced a regression — not the routine.

There is no conflict with Kargo, because Kargo never gets asked to own the
Kubernetes version. Making it own that version is the alternative we reject:
you would pin every cluster with `NO_MINOR_UPGRADES`, drive
`min_master_version` from the pipeline, and inherit the full 14-month clock
including the obligation to ship a bump before Google overrides you anyway. It
buys a soak that windows already provide, and under a flat fee we would be
paying for it out of our own margin.

**Honest limitation.** Three to four days is thin soak for a minor version. A
client who needs weeks can have them through *staged channels* — dev on Rapid,
staging on Regular, prod on Stable, which is five to six months of soak for
free — at the cost of running two or three different minor versions across one
estate at all times. That makes the socle's compatibility matrix the thing that
has to be widened, which is a cost paid in the catalog rather than in ops. It
is a catalog option, not the default, and it feeds the multi-cloud homogeneity
synthesis.

## 2. Add-ons

### Observability: is Managed Service for Prometheus really expensive?

Partly. The claim needs splitting in three, because Google bills the three
differently.

**GKE system metrics and logs are free of ingestion charge** and cannot be
turned off on Autopilot anyway. Nothing to decide.

**Control plane metrics** (`APISERVER`, `SCHEDULER`, `CONTROLLER_MANAGER`) and
**kube-state metrics** (`POD`, `DEPLOYMENT`, `STATEFULSET`, `DAEMONSET`,
`STORAGE`, `HPA`) are off by default and billed per sample as soon as they are
enabled. They stay off in the module's defaults.

**Everything the catalog scrapes** goes through managed collection and is
billed at **$0.06 per million samples** for the first 50 billion a month. One
sample per second, ingested for a month, is 2.63 million samples — so the only
unit worth remembering is:

```
$0.158 per month per sample/second ingested
```

Google's own cost-control documentation puts an unfiltered `kube-prometheus`
install on a three-node cluster at roughly **900 samples/second**. That is
**$142 per cluster per month**, or $426 across the reference estate — **+29%**
on a $1,488 bill, for metrics. Filtering as Google recommends (dropping the
apiserver ServiceMonitor is ~200 samples/s, trimming kube-state-metrics to core
resources another ~125) brings a realistic catalog target to ~300 samples/s, or
**$47 per cluster per month**.

The alternative is our own Prometheus, and on Autopilot it is not free either,
because Pod requests are the billing unit. A single-replica Prometheus at
2 vCPU / 8 GiB is $94 a month, Grafana and Alertmanager add about $30, and a
100 GiB balanced PD another $10 — **$134 per cluster per month** before
anyone's time. Which gives the crossover:

```
Below ~850 samples/second per cluster, GMP is cheaper than running our own.
Above it, self-hosting wins on hard cost — and costs us the operating time.
```

**Recommendation: delegate to GMP.** A socle cluster at the recommended
filtering level sits at a third of the crossover, Monarch retains 24 months at
no extra cost where a self-hosted Prometheus retains fifteen days, and the
operating burden lands on Google rather than on a flat fee. What this makes
non-negotiable is that **the catalog's monitoring module carries a
samples/second budget as an acceptance criterion** — GMP turns cardinality
directly into invoice, and nothing in the module can protect a client from a
chatty exporter.

Two traps to state plainly. **GKE Auto-Monitoring** (`auto_monitoring_config`
scope `ALL`) automatically deploys `PodMonitoring` for detected workloads: the
feature is free, the samples it starts ingesting are not. It stays off.
And **Cloud Logging** bills $0.50/GiB past 50 GiB free per project per month —
invisible at 30 GiB per cluster, $125 a month for an estate producing 100 GiB
per cluster. The module exposes the logging components so `WORKLOADS` can be
dropped; exclusion filters belong to the catalog.

### Backup: Backup for GKE or Velero?

Backup for GKE bills two ways: **$9.00 per non-system namespace per month**,
and **$0.045 per GiB-month** of backup storage. It supports Autopilot, it backs
up config plus Persistent Disk volume snapshots, it restores across clusters
and projects with transformation rules, and it does not back up anything that
is not a PD persistent volume — no NFS, no NetApp, Filestore only through
custom hooks.

Note which half is expensive. A raw PD standard snapshot costs $0.05/GiB-month,
so Backup for GKE's *storage* is slightly cheaper than doing it yourself. The
$9 per namespace-month is the whole surcharge. On the reference estate, at ten
non-system namespaces per cluster and 600 GiB of volumes, that is **$297 a
month — +20%**. Protecting production only is $113.

Velero on the same estate is a controller Pod per cluster (~$20), CSI
VolumeSnapshots of the same 600 GiB (~$30 at the PD snapshot rate) and a
negligible GCS bucket for config: **about $90 a month**, and the same runbook
on EKS, AKS and Kapsule.

But Autopilot cuts one of Velero's legs off. Velero's node-agent — which is
what performs file-system backup and the built-in data mover for CSI snapshots
— needs a writable `hostPath` under the kubelet directory and, in most
environments, privileged mode. Autopilot blocks privileged containers and host
namespaces outside Google's partner allowlist, and permits `hostPath` only as
read-only access to `/var/log`. So on Autopilot, Velero gives us **config
backup plus CSI volume snapshots that stay inside Google Cloud**, and no
file-level backup and no portable copy of volume data in object storage.

**Recommendation: Velero as the catalog default, Backup for GKE as a priced
option.** Velero at three times less cost covers what a PD-backed socle
actually needs, and it is the only one of the two that gives a single restore
procedure across four clouds — exactly the kind of work that industrialises to
near-zero marginal cost. Backup for GKE earns its $9 per namespace when a
client needs managed cross-project restore or has a compliance requirement
naming a managed service; then it is opt-in and priced through. The module's
only job is the agent add-on toggle, off by default; backup plans themselves
are catalog resources provisioned by Crossplane.

### Config Connector versus Crossplane: is there a new fact?

No, and Autopilot closes the question rather than us.

The Config Connector GKE add-on is **available on Standard clusters only**, and
Google discourages it in production regardless, because the add-on's version
lags upstream Config Connector by up to twelve months. Config Connector also
appears in the Extended channel's incompatibility list, alongside Autopilot
mode itself. What remains is either installing Config Connector ourselves — the
same operating burden as Crossplane, on a narrower community — or Config
Controller, a separate Google-managed cluster, which contradicts the socle's
premise that infrastructure is reconciled from inside the client's own cluster.

**Confirmed and closed. Crossplane stays. Config Connector is absent from the
module**, not exposed as an option.

## 3. Identity

### Workload Identity Federation for GKE

Autopilot pre-configures it and it cannot be disabled, so **there is no module
variable** — only the outputs the socle needs. The pool is
`PROJECT_ID.svc.id.goog`, and a workload's principal is:

```
principal://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/
  workloadIdentityPools/PROJECT_ID.svc.id.goog/subject/ns/NAMESPACE/sa/KSA
```

Two ways to use it: grant IAM roles to that principal directly, or have the
workload impersonate a Google service account. Direct grants are the better
default for catalog workloads — no service account to create, rotate or audit —
and impersonation is the fallback for the APIs that still require it.

One trap worth writing down: the principal identifier is built from namespace
and service account name, so **two clusters in the same project produce
identical principals for the same namespace/KSA pair**. Per-cluster isolation
needs either distinct namespaces or IAM conditions, and a three-environment
estate in one project has no isolation at all. That is a network-and-project
layout decision and belongs to the base security research, but the module has
to be built knowing it.

### The identity the Crossplane provider assumes

This one does *not* get to use direct principals. The Upbound GCP provider
family's `ProviderConfig` accepts `Secret`, `AccessToken`,
`ImpersonateServiceAccount`, `Upbound` and `InjectedIdentity`, and
`InjectedIdentity` is documented as resolving Application Default Credentials
through **a Google service account named in the provider's Kubernetes service
account annotation** `iam.gke.io/gcp-service-account`, with a
`roles/iam.workloadIdentityUser` binding on
`serviceAccount:PROJECT.svc.id.goog[crossplane-system/KSA]`. So a Google
service account is required, and the module must create it.

Which surfaces a real interface problem: the provider Pod's service account
name is not stable across provider revisions unless the socle pins it with a
`DeploymentRuntimeConfig`. The binding the module creates has to name that
service account, so **the KSA name is a module input with a default matching
the socle's `DeploymentRuntimeConfig`** — the two have to agree, and the
checklist's "single apply converges" rule means the module cannot discover it
at runtime.

Roles on that service account stay a variable with a deliberately empty
default: the catalog does not exist yet, so any list we wrote today would be a
guess presented as a recommendation.

## Cost impact on the reference estate

Same estate as the [cluster mode research](README.md): production 20 vCPU /
40 GiB of Pod requests, staging 8 / 16, dev 4 / 8, three Autopilot clusters,
us-central1 list price, 730-hour month. Baseline **$1,488/month**.

| | Per month | vs baseline |
| --- | --- | --- |
| Baseline (Autopilot Pods + cluster fees) | $1,488 | — |
| GMP, catalog filtered to ~300 samples/s per cluster | +$142 | +10% |
| Cloud Logging, 30 GiB per cluster in one project | +$20 | +1% |
| Velero, config + CSI snapshots of 600 GiB | +$90 | +6% |
| **Recommended position** | **$1,740** | **+17%** |
| | | |
| *Maximal delegation, for comparison* | | |
| GMP unfiltered at ~900 samples/s per cluster | +$426 | +29% |
| Backup for GKE, 30 namespaces + 600 GiB | +$297 | +20% |
| Extended channel past standard support (impossible on Autopilot) | +$1,095 | +74% |

Rates used: Autopilot container-optimized $0.0445/vCPU-hour and
$0.0049225/GiB-hour; cluster management fee $0.10/cluster-hour; extended
support $0.50/cluster-hour; GMP $0.06 per million samples; Cloud Logging
$0.50/GiB past 50 GiB free per project; Backup for GKE $9.00/namespace-month
and $0.045/GiB-month; PD standard snapshot $0.05/GiB-month; PD balanced
$0.10/GiB-month. All us-central1, list price, read 8 September 2026. GKE's free
tier ($74.40 of monthly credits per billing account) is ignored throughout.
Re-price before quoting.

## Module specification

| Variable | Type | Default | Constraint |
| --- | --- | --- | --- |
| `release_channel` | `string` | `"REGULAR"` | one of `RAPID`, `REGULAR`, `STABLE`; `EXTENDED` rejected |
| `maintenance_window` | `object({ start_time, duration, recurrence })` | **none — required** | duration ≥ 4h, and duration × weekly occurrences ≥ 48h per 92 days |
| `maintenance_exclusions` | `list(object({ name, start_time, end_time, scope }))` | `[]` | scope in the three documented values; `NO_UPGRADES` ≤ 90 days; ≤ 3 of that scope, ≤ 20 total |
| `kubernetes_min_version` | `string` | `null` | raise-only escape hatch, documented as exceptional |
| `enable_upgrade_notifications` | `bool` | `true` | module creates the Pub/Sub topic and outputs it |
| `logging_components` | `list(string)` | `["SYSTEM_COMPONENTS", "WORKLOADS"]` | `SYSTEM_COMPONENTS` cannot be removed |
| `monitoring_components` | `list(string)` | `["SYSTEM_COMPONENTS"]` | billed components accepted but never defaulted |
| `backup_agent_enabled` | `bool` | `false` | — |
| `crossplane_service_account_namespace` | `string` | `"crossplane-system"` | — |
| `crossplane_service_account_name` | `string` | `"provider-gcp"` | must match the socle's `DeploymentRuntimeConfig` |
| `crossplane_project_roles` | `list(string)` | `[]` | set once the catalog's needs are known |

Absent by decision, and not to be added without revisiting this document:
`EXTENDED` as a channel value, any Config Connector toggle, any Workload
Identity toggle, `auto_monitoring_config`, and `gke_auto_upgrade_config`.

Outputs this document adds to the checklist's list: the workload identity pool,
the Crossplane service account email, and the upgrade-notification topic.

## Known gaps

- **The samples/second budget is a target, not a measurement.** The $142 line
  in the cost table assumes the catalog's monitoring module lands at ~300
  samples/s per cluster. The catalog does not exist at pre-0.1.0. Until it is
  measured on a real cluster, GMP's cost is the least certain number here.
- **Velero's coverage on Autopilot is argued from documentation, not tested.**
  That node-agent cannot run under Autopilot's restrictions follows from
  Velero's requirements and Autopilot's allowlist; it has not been verified
  against a running cluster, and it is the single fact the backup
  recommendation rests on.
- **The 48h/92-day rule cannot be fully validated in HCL.** The module can
  check a window's own arithmetic, but not the interaction between a window and
  a set of exclusions across a rolling period. That check belongs in the
  factory.
- **Google's own pages disagree on the rolling period** — 92 days on the
  maintenance pages, 32 days in some summaries. This document follows the
  maintenance how-to and concepts pages, which both say 92.
- **Principal collision between environments in one project** is recorded here
  but decided in the base network and security research.
- **Config Connector installed manually on Autopilot** was not evaluated. The
  decision does not depend on it: the add-on path is closed and the manual path
  offers nothing over Crossplane.

## Sources

Read 8 September 2026.

- [About release channels][channels] — channel timings, Extended channel
  limitations including Autopilot, Autopilot must be enrolled in a channel
- [GKE versioning and support][versioning] — 14 months standard, 24 with
  extended
- [Maintenance windows and exclusions][maint-concepts] ·
  [how-to][maint-howto] — exclusion scopes and caps, 48h per 92-day rolling
  window
- [Autopilot cluster upgrades][autopilot-upgrades] — surge upgrades, what is
  and is not deferrable
- [GKE pricing][pricing] — cluster fee, extended support $0.50/cluster-hour,
  Autopilot Pod rates, Backup for GKE
- [Google Cloud Observability pricing][obs-pricing] — GMP $0.06 per million
  samples, Logging $0.50/GiB
- [About GKE metrics][gke-metrics] — system metrics free, control plane and
  kube-state billed
- [Managed Service for Prometheus cost controls][gmp-costs] — 900 samples/s
  baseline, filtering gains
- [Automatic application monitoring][auto-mon] — free feature, billed samples
- [Backup for GKE][backup-gke] — Autopilot support, PD-only volume backup
- [Autopilot security restrictions][autopilot-security] · [Velero file system
  backup][velero-fsb] — privileged, host namespaces, `hostPath`
- [Config Connector installation types][kcc-install] — Standard-only add-on,
  version lag
- [Workload Identity Federation for GKE][wif] — principal identifiers, direct
  access vs impersonation
- [Upbound GCP provider authentication][upbound-auth] — `InjectedIdentity`
  requires a Google service account
- [Disk and image pricing][disks] — PD balanced, standard snapshots
- [`google_container_cluster`][tf-cluster] — the field names the module uses

[channels]: https://cloud.google.com/kubernetes-engine/docs/concepts/release-channels
[versioning]: https://cloud.google.com/kubernetes-engine/versioning
[maint-concepts]: https://cloud.google.com/kubernetes-engine/docs/concepts/maintenance-windows-and-exclusions
[maint-howto]: https://cloud.google.com/kubernetes-engine/docs/how-to/maintenance-windows-and-exclusions
[autopilot-upgrades]: https://cloud.google.com/kubernetes-engine/docs/concepts/cluster-upgrades-autopilot
[pricing]: https://cloud.google.com/kubernetes-engine/pricing
[obs-pricing]: https://cloud.google.com/stackdriver/pricing
[gke-metrics]: https://cloud.google.com/stackdriver/docs/solutions/gke/managing-metrics
[gmp-costs]: https://cloud.google.com/stackdriver/docs/managed-prometheus/cost-controls
[auto-mon]: https://cloud.google.com/kubernetes-engine/docs/how-to/configure-automatic-application-monitoring
[backup-gke]: https://cloud.google.com/kubernetes-engine/docs/add-on/backup-for-gke/concepts/backup-for-gke
[autopilot-security]: https://cloud.google.com/kubernetes-engine/docs/concepts/autopilot-security
[velero-fsb]: https://velero.io/docs/main/file-system-backup/
[kcc-install]: https://cloud.google.com/config-connector/docs/concepts/installation-types
[wif]: https://cloud.google.com/kubernetes-engine/docs/concepts/workload-identity
[upbound-auth]: https://docs.upbound.io/providers/provider-gcp/authentication
[disks]: https://cloud.google.com/compute/disks-image-pricing
[tf-cluster]: https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/container_cluster
