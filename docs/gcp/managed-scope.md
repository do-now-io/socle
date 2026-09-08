# GKE managed scope: upgrades, add-ons, identity

What Google operates and what we operate, on an Autopilot cluster — see
[cluster mode](cluster-mode.md).

| Question | Position |
| --- | --- |
| Kubernetes minor version | Google's release channel decides |
| Which cluster upgrades first | Ours, through the maintenance window |
| Extended channel | Refused — impossible on Autopilot |
| System metrics and logs | Google's — free, not disableable |
| Control plane / kube-state metrics | Catalog option — billed per sample |
| Workload metrics | Managed Service for Prometheus |
| GKE Auto-Monitoring | Refused as a default — silent per-sample cost |
| Backup | Velero, the same on four clouds |
| Backup for GKE | Catalog option — $9 per namespace-month |
| Workload Identity Federation | Google's — pre-configured, not optional |

## Upgrades

Kubernetes ships three minor versions a year and GKE supports each for about
14 months, so upgrading twice a year is the floor. The Extended channel would
stretch that to 24 months, but Google forbids it on Autopilot, so the option
does not exist.

| Channel | Minor arrives | Notes |
| --- | --- | --- |
| Rapid | 1–2 weeks after upstream GA | **Outside the GKE SLA** |
| Regular (default) | ~2 months after Rapid | Google's recommendation |
| Stable | 3–4 months after Regular | Changes land here last |

**Decision: one channel for the whole estate, `REGULAR`, and the ring order
comes from the maintenance window — dev Tuesday, staging Wednesday, prod
Saturday.** Kargo keeps owning the socle artifact; the Kubernetes version
stays Google's. Two clocks, one owner each.

Why not let Kargo own the version: you would pin every cluster with a
`NO_MINOR_UPGRADES` exclusion and drive the version from the pipeline,
inheriting the whole 14-month clock — including having to ship a bump before
Google overrides the exclusion at end of support anyway. Window skew gives the
same ordering for free.

The window is a **required** variable with no default: a silent default means
nobody decided when production gets upgraded. GKE also requires at least 48
hours of maintenance availability in any 92-day window, counting only blocks
of four hours or more.

## Add-ons

### Managed Service for Prometheus

System metrics are free and not disableable. Control plane and kube-state
metrics are billed per sample, so they stay off by default. What the catalog
scrapes costs **$0.158 per month per sample/second ingested**.

| Per cluster | Samples/s | Per month |
| --- | --- | --- |
| Unfiltered `kube-prometheus` (Google's figure) | ~900 | $142 |
| Filtered as Google recommends | ~300 | $47 |
| Self-hosted Prometheus + Grafana + 100 GiB disk | n/a | $134 |

**Decision: delegate to GMP.** The crossover is ~850 samples/s per cluster, a
filtered cluster sits at a third of that, and Monarch keeps 24 months where a
self-hosted Prometheus keeps fifteen days. The consequence is binding: **the
catalog's monitoring module must carry a samples/second budget**, because GMP
turns cardinality straight into invoice.

Auto-Monitoring stays off — the feature is free, the samples it starts
ingesting are not.

### Backup

Backup for GKE costs **$9 per non-system namespace-month** plus $0.045/GiB. On
the reference estate that is $297/month; Velero over the same scope is ~$90 and
gives one restore procedure across four clouds.

Autopilot does cut one of Velero's legs off: its node-agent needs privileged
mode and a writable `hostPath`, both blocked. So Velero covers config plus CSI
volume snapshots, and no portable copy of volume data.

**Decision: Velero by default, Backup for GKE as a priced option** when a
client needs managed cross-project restore.

## Identity

Autopilot pre-configures Workload Identity Federation and it cannot be
disabled, so there is nothing to configure — the pool is
`PROJECT_ID.svc.id.goog`.

**Decision: workloads that need Google Cloud access get a Google service
account, bound to their Kubernetes service account.** That is all the shell
needs today.

One trap worth knowing: a workload's principal is built from its namespace and
service account name, so two clusters in the same project produce identical
principals for the same pair. Isolation comes from separate projects or
distinct namespaces — a decision for the base network and security work.

## Cost impact

Reference estate of three Autopilot clusters, baseline **$1,488/month**.

| | Per month | vs baseline |
| --- | --- | --- |
| GMP, filtered to ~300 samples/s per cluster | +$142 | +10% |
| Cloud Logging, 30 GiB per cluster | +$20 | +1% |
| Velero | +$90 | +6% |
| **Recommended position** | **$1,740** | **+17%** |
| *Backup for GKE instead of Velero* | +$297 | +20% |
| *GMP unfiltered* | +$426 | +29% |

us-central1 list price, read 8 September 2026. Re-price before quoting.

## Module specification

| Variable | Default | Constraint |
| --- | --- | --- |
| `release_channel` | `"REGULAR"` | `RAPID`, `REGULAR` or `STABLE`; `EXTENDED` rejected |
| `maintenance_window` | **none — required** | ≥ 4h, and ≥ 48h per 92 days |
| `maintenance_exclusions` | `[]` | `NO_UPGRADES` ≤ 90 days, ≤ 3 of that scope |
| `kubernetes_min_version` | `null` | raise-only escape hatch |
| `enable_upgrade_notifications` | `true` | module creates the Pub/Sub topic |
| `logging_components` | `["SYSTEM_COMPONENTS", "WORKLOADS"]` | `SYSTEM_COMPONENTS` cannot be removed |
| `monitoring_components` | `["SYSTEM_COMPONENTS"]` | billed components accepted, never defaulted |
| `backup_agent_enabled` | `false` | — |

Absent by decision: `EXTENDED`, any Workload Identity toggle,
`auto_monitoring_config`, `gke_auto_upgrade_config`.

## Known gaps

- **The ~300 samples/s target is not a measurement.** The catalog does not
  exist yet, so GMP's cost is the least certain number here.
- **Velero's node-agent limit on Autopilot is read from documentation, not
  tested**, and the backup recommendation rests on it.

## Sources

Read 8 September 2026. [Release channels][channels] ·
[versioning and support][versioning] · [maintenance windows and
exclusions][maint] · [GKE pricing][pricing] · [Observability
pricing][obs-pricing] · [About GKE metrics][gke-metrics] · [GMP cost
controls][gmp-costs] · [Backup for GKE][backup-gke] · [Velero file system
backup][velero-fsb] · [Workload Identity Federation][wif].

[channels]: https://cloud.google.com/kubernetes-engine/docs/concepts/release-channels
[versioning]: https://cloud.google.com/kubernetes-engine/versioning
[maint]: https://cloud.google.com/kubernetes-engine/docs/concepts/maintenance-windows-and-exclusions
[pricing]: https://cloud.google.com/kubernetes-engine/pricing
[obs-pricing]: https://cloud.google.com/stackdriver/pricing
[gke-metrics]: https://cloud.google.com/stackdriver/docs/solutions/gke/managing-metrics
[gmp-costs]: https://cloud.google.com/stackdriver/docs/managed-prometheus/cost-controls
[backup-gke]: https://cloud.google.com/kubernetes-engine/docs/add-on/backup-for-gke/concepts/backup-for-gke
[velero-fsb]: https://velero.io/docs/main/file-system-backup/
[wif]: https://cloud.google.com/kubernetes-engine/docs/concepts/workload-identity
