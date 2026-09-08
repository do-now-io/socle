# GKE managed scope: upgrades, add-ons, identity

Which parts of a GKE cluster Google operates, and which the socle operates
itself. Autopilot throughout — see [cluster mode](README.md).

| Question | Position | In the module |
| --- | --- | --- |
| Kubernetes minor version | Google's release channel decides | `release_channel`, default `REGULAR` |
| Which cluster upgrades first | Ours — maintenance-window skew | `maintenance_window`, required |
| Blocking an upgrade | Ours, exceptionally | `maintenance_exclusions`, default empty |
| Extended channel | Refused — impossible on Autopilot | absent |
| System metrics and logs | Google's — free, not disableable | `logging_components`, `monitoring_components` |
| Control plane / kube-state metrics | Catalog option — billed per sample | in `monitoring_components`, off by default |
| GKE Auto-Monitoring | Refused as a default — silent per-sample cost | absent |
| Workload metrics | Managed Service for Prometheus | managed collection on, catalog owns what is scraped |
| Backup | Ours — Velero, same on four clouds | `backup_agent_enabled`, default `false` |
| Backup for GKE | Catalog option — $9 per namespace-month | same variable, opt-in |
| Config Connector | Refused — Crossplane confirmed | absent |
| Workload Identity Federation | Google's — pre-configured, not optional | no variable, outputs only |
| The Crossplane provider's identity | Ours — module creates it | `crossplane_*` variables |

## 1. Upgrades

| Channel | Minor arrives | Auto-upgrade target | Notes |
| --- | --- | --- | --- |
| Rapid | 1–2 weeks after upstream GA | 1–2 months later | **Excluded from the GKE SLA** |
| Regular (default) | ~2 months after Rapid | ~3 months later | Google's own recommendation |
| Stable | 3–4 months after Regular | ~2 months later | Changes land here last |
| Extended | aligned with Regular | aligned with Regular | **Forbidden on Autopilot** |

Three minor versions a year, ~14 months of standard support each from the
moment one reaches Regular. Extended would stretch that to 24, but Google's
limitation list names *Autopilot cluster mode* as disqualifying, so the option
does not exist here. Its price, for the multi-cloud synthesis: $0.50 per
cluster-hour once the minor passes end of standard support, **+$1,095/month
(+74%)** on the reference estate, to defer work that happens anyway. Autopilot
clusters can only be enrolled in a channel, and the deprecated "no channel"
option disappears on 14 June 2027.

### Who decides the moment: channels or Kargo rings?

**Two clocks, one owner each.** The socle artifact is Kargo's, promoted
dev → staging → prod on our schedule. The Kubernetes minor version is Google's,
and the levers are: the **channel** (which version, estate-wide); the
**maintenance window** (when in the week — the only per-cluster ordering lever
with nothing to maintain); **exclusions** (`NO_UPGRADES`, 90 days max and three
at most; `NO_MINOR_UPGRADES`; `NO_MINOR_OR_NODE_UPGRADES` — explicit date
ranges, so a rolling exclusion is something we keep rewriting);
**`min_master_version`** (a floor, and raising it forces an upgrade — the only
lever that promotes on our command); **`disruption_budget`** (minimum interval
between two minor, or two patch, control plane upgrades); and **Pub/Sub
notifications**. One hard constraint shapes all of it: a cluster must be left
**at least 48 hours of maintenance availability in any 92-day rolling window**,
counting only contiguous blocks of four hours or more. Exclusions are
deactivated at end of standard support, upgraded, then reactivated against the
next deadline — the 14-month clock cannot be outrun, only positioned in.

**Recommendation.** One channel for the estate, `REGULAR`, with ring order from
*window skew inside the week*: dev Tuesday, staging Wednesday, prod Saturday.
Declarative, no dates to roll forward, every cluster on the same minor,
deterministic order, three to four days of soak per hop. Rapid is refused for
anything a client depends on, being outside the SLA. `NO_MINOR_UPGRADES` is the
brake pulled when dev or staging surfaced a regression, not the routine.

Nothing conflicts with Kargo because Kargo is never asked to own the Kubernetes
version — the rejected alternative, which would pin every cluster and drive
`min_master_version` from the pipeline, inheriting the whole 14-month clock and
the obligation to ship a bump before Google overrides the exclusion anyway, to
buy a soak that windows already give.

**Limitation.** Three to four days is thin for a minor version. Weeks are
available through *staged channels* — dev Rapid, staging Regular, prod Stable,
five to six months of soak for free — at the cost of two or three minors across
one estate permanently, which widens the socle's compatibility matrix. Catalog
option, not the default.

## 2. Add-ons

### Managed Service for Prometheus

The cost reputation is half deserved, because Google bills three things
differently. **System metrics and logs** are free and not disableable on
Autopilot. **Control plane metrics** (`APISERVER`, `SCHEDULER`,
`CONTROLLER_MANAGER`) and **kube-state metrics** (`POD`, `DEPLOYMENT`,
`STATEFULSET`, `DAEMONSET`, `STORAGE`, `HPA`) are off by default and billed per
sample once enabled — they stay off. **What the catalog scrapes** costs $0.06
per million samples up to 50 billion a month, so the unit to remember is
**$0.158 per month per sample/second ingested**.

| Per cluster | Samples/s | Per month |
| --- | --- | --- |
| Unfiltered `kube-prometheus`, Google's own figure | ~900 | $142 |
| Filtered as Google recommends | ~300 | $47 |
| Self-hosted Prometheus + Grafana + 100 GiB PD | n/a | $134 |

Autopilot bills Pod requests, so self-hosting is not free: crossover is
**~850 samples/second per cluster**, below which GMP is cheaper, above which
self-hosting wins on hard cost and costs us the operating time.

**Delegate to GMP.** A filtered cluster sits at a third of the crossover, and
Monarch retains 24 months where a self-hosted Prometheus retains fifteen days.
One consequence is binding: **the catalog's monitoring module must carry a
samples/second budget as an acceptance criterion**, because GMP turns
cardinality straight into invoice and no module setting protects a client from
a chatty exporter.

Two traps. **Auto-Monitoring** (`auto_monitoring_config` scope `ALL`) deploys
`PodMonitoring` for detected workloads — the feature is free, the samples are
not, so it stays off. **Cloud Logging** bills $0.50/GiB past 50 GiB free per
project: invisible at 30 GiB per cluster, $125/month at 100 GiB per cluster.
The module exposes the logging components so `WORKLOADS` can be dropped;
exclusion filters belong to the catalog.

### Backup for GKE or Velero

Backup for GKE bills **$9.00 per non-system namespace-month** plus **$0.045 per
GiB-month**. It supports Autopilot, covers config plus Persistent Disk
snapshots, restores across clusters and projects, and covers nothing that is
not a PD volume — no NFS, no NetApp, Filestore only through custom hooks.

Note which half is expensive: a raw PD snapshot is $0.05/GiB-month, so its
*storage* is marginally cheaper than doing it ourselves, and the $9 per
namespace-month is the entire surcharge — **$297/month (+20%)** on the
reference estate at ten non-system namespaces per cluster and 600 GiB, or $113
for production only. Velero over the same scope is ~$20 of controller Pod per
cluster plus ~$30 of CSI snapshots: **~$90/month**, with one runbook for EKS,
AKS and Kapsule too.

Autopilot does cut one of Velero's legs off. Its node-agent — file-system
backup and the data mover for CSI snapshots — needs a writable `hostPath` under
the kubelet directory and usually privileged mode, and Autopilot blocks
privileged containers and host namespaces outside Google's partner allowlist,
permitting `hostPath` only read-only on `/var/log`. So Velero gives config
backup plus CSI snapshots that stay inside Google Cloud, with no file-level
backup and no portable copy of volume data in object storage.

**Velero as the catalog default, Backup for GKE opt-in.** Velero covers what a
PD-backed socle needs at a third of the cost with one restore procedure across
four clouds; Backup for GKE earns its $9 per namespace when managed
cross-project restore or a compliance requirement naming a managed service is
in play. The module's only job is the agent toggle — backup plans are catalog
resources provisioned by Crossplane.

### Config Connector versus Crossplane

Nothing new, and Autopilot closes the question rather than us. The add-on is
**Standard-only**, Google discourages it in production anyway because it lags
upstream by up to twelve months, and Config Connector sits in the Extended
channel's incompatibility list next to Autopilot itself. What remains is
installing it ourselves — the same operating burden as Crossplane on a narrower
community — or Config Controller, a separate Google-managed cluster, which
contradicts the premise that infrastructure is reconciled from inside the
client's own cluster. **Confirmed and closed: Crossplane stays, Config
Connector is absent from the module** rather than exposed as an option.

## 3. Identity

Autopilot pre-configures Workload Identity Federation and it cannot be
disabled, so **there is no module variable** — only outputs. The pool is
`PROJECT_ID.svc.id.goog`, and a workload's principal is
`principal://iam.googleapis.com/projects/NUMBER/locations/global/workloadIdentityPools/PROJECT_ID.svc.id.goog/subject/ns/NAMESPACE/sa/KSA`.
Roles go to that principal directly — the better default for catalog workloads,
nothing to create, rotate or audit — or through impersonation for the APIs that
still require it. The trap: principals are built from namespace and service
account name, so **two clusters in one project produce identical principals for
the same namespace/KSA pair**. Isolation needs distinct namespaces or IAM
conditions; the decision belongs to the base network and security research, but
the module has to be built knowing it.

**The Crossplane provider does not get direct principals.** The Upbound GCP
provider family's `ProviderConfig` accepts `Secret`, `AccessToken`,
`ImpersonateServiceAccount`, `Upbound` and `InjectedIdentity`, and
`InjectedIdentity` resolves Application Default Credentials through a Google
service account named in the provider's Kubernetes service account annotation
`iam.gke.io/gcp-service-account`, with a `roles/iam.workloadIdentityUser`
binding on `serviceAccount:PROJECT.svc.id.goog[crossplane-system/KSA]`. The
module therefore creates that service account — and since the provider Pod's
KSA name is not stable across provider revisions unless the socle pins it with
a `DeploymentRuntimeConfig`, **the KSA name is a module input** whose default
has to agree with the socle. Its roles stay a variable with an empty default:
the catalog does not exist yet, and any list written today would be a guess
presented as a recommendation.

## Cost impact on the reference estate

Same estate as the [cluster mode research](README.md): production 20 vCPU /
40 GiB of Pod requests, staging 8 / 16, dev 4 / 8, three Autopilot clusters,
us-central1 list price, 730-hour month. Baseline **$1,488/month**.

| | Per month | vs baseline |
| --- | --- | --- |
| GMP, catalog filtered to ~300 samples/s per cluster | +$142 | +10% |
| Cloud Logging, 30 GiB per cluster in one project | +$20 | +1% |
| Velero, config + CSI snapshots of 600 GiB | +$90 | +6% |
| **Recommended position** | **$1,740** | **+17%** |
| *GMP unfiltered at ~900 samples/s per cluster* | +$426 | +29% |
| *Backup for GKE, 30 namespaces + 600 GiB* | +$297 | +20% |
| *Extended channel past standard support (impossible here)* | +$1,095 | +74% |

Rates, all us-central1 list price read 8 September 2026: Autopilot
container-optimized $0.0445/vCPU-hour and $0.0049225/GiB-hour; cluster fee
$0.10/cluster-hour; extended support $0.50/cluster-hour; GMP $0.06 per million
samples; Logging $0.50/GiB past 50 GiB free per project; Backup for GKE
$9.00/namespace-month and $0.045/GiB-month; PD standard snapshot
$0.05/GiB-month; PD balanced $0.10/GiB-month. The GKE free tier ($74.40 of
monthly credits per billing account) is ignored. Re-price before quoting.

## Module specification

| Variable | Type | Default | Constraint |
| --- | --- | --- | --- |
| `release_channel` | `string` | `"REGULAR"` | `RAPID`, `REGULAR` or `STABLE`; `EXTENDED` rejected |
| `maintenance_window` | `object({ start_time, duration, recurrence })` | **none — required** | duration ≥ 4h, and duration × weekly occurrences ≥ 48h per 92 days |
| `maintenance_exclusions` | `list(object({ name, start_time, end_time, scope }))` | `[]` | documented scopes only; `NO_UPGRADES` ≤ 90 days, ≤ 3 of that scope, ≤ 20 total |
| `kubernetes_min_version` | `string` | `null` | raise-only escape hatch, documented as exceptional |
| `enable_upgrade_notifications` | `bool` | `true` | module creates the Pub/Sub topic and outputs it |
| `logging_components` | `list(string)` | `["SYSTEM_COMPONENTS", "WORKLOADS"]` | `SYSTEM_COMPONENTS` cannot be removed |
| `monitoring_components` | `list(string)` | `["SYSTEM_COMPONENTS"]` | billed components accepted, never defaulted |
| `backup_agent_enabled` | `bool` | `false` | — |
| `crossplane_service_account_namespace` | `string` | `"crossplane-system"` | — |
| `crossplane_service_account_name` | `string` | `"provider-gcp"` | must match the socle's `DeploymentRuntimeConfig` |
| `crossplane_project_roles` | `list(string)` | `[]` | set once the catalog's needs are known |

Absent by decision, not to be added without revisiting this document:
`EXTENDED` as a channel value, any Config Connector or Workload Identity
toggle, `auto_monitoring_config`, `gke_auto_upgrade_config`. Outputs this adds
to the checklist's list: the workload identity pool, the Crossplane service
account email, the upgrade-notification topic.

## Known gaps

- **The samples/second budget is a target, not a measurement.** The $142 line
  assumes the catalog lands at ~300 samples/s per cluster; the catalog does not
  exist at pre-0.1.0, so GMP's cost is the least certain number here.
- **Velero's coverage on Autopilot is argued from documentation, not tested.**
  That node-agent cannot run under Autopilot's restrictions follows from
  Velero's requirements and Autopilot's allowlist, and the backup
  recommendation rests on it.
- **The 48h/92-day rule cannot be fully validated in HCL** — a window's own
  arithmetic can be, its interaction with a set of exclusions cannot. Google's
  own pages also disagree on the period (92 days on the maintenance pages, 32
  in some summaries); this follows the two that say 92.
- **Principal collision between environments in one project** is recorded here
  but decided in the base network and security research.
- **Config Connector installed manually on Autopilot** was not evaluated. The
  decision does not depend on it: the add-on path is closed and the manual path
  offers nothing over Crossplane.

## Sources

Read 8 September 2026. [Release channels][channels] ·
[versioning and support][versioning] · [maintenance windows and
exclusions][maint-concepts] and [how-to][maint-howto] · [Autopilot cluster
upgrades][autopilot-upgrades] · [GKE pricing][pricing] · [Observability
pricing][obs-pricing] · [About GKE metrics][gke-metrics] · [GMP cost
controls][gmp-costs] · [automatic application monitoring][auto-mon] ·
[Backup for GKE][backup-gke] · [Autopilot security
restrictions][autopilot-security] · [Velero file system backup][velero-fsb] ·
[Config Connector installation types][kcc-install] · [Workload Identity
Federation for GKE][wif] · [Upbound GCP provider
authentication][upbound-auth] · [disk and image pricing][disks] ·
[`google_container_cluster`][tf-cluster].

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
