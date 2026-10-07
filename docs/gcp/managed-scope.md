# GKE managed scope: upgrades, add-ons, identity

Who operates what on an Autopilot cluster — see
[cluster mode](cluster-mode.md).

| Question | Position |
| --- | --- |
| Kubernetes minor version | Google's release channel decides |
| Which cluster upgrades first | Ours, through the maintenance window |
| Extended channel | Refused — forbidden on Autopilot |
| System metrics and logs | Google's — free, not disableable |
| Control plane / kube-state metrics | Catalog option — billed per sample |
| Workload metrics | Managed Service for Prometheus |
| Auto-Monitoring | Refused as a default — silent per-sample cost |
| Backup | Velero, the same on four clouds |
| Backup for GKE | Catalog option — $9 per namespace-month |
| Workload Identity Federation | Google's — pre-configured, not optional |
| Google service accounts | None — each workload is its own principal |

## Upgrades

Three Kubernetes minors a year, ~14 months of support each: upgrading twice a
year is the floor. Extended support would double that, but Google forbids the
Extended channel on Autopilot.

| Channel | Minor arrives | Notes |
| --- | --- | --- |
| Rapid | 1–2 weeks after upstream release | **Outside the GKE SLA** |
| Regular (default) | ~2 months after Rapid | Google's recommendation |
| Stable | 3–4 months after Regular | Changes land here last |

**Decision: one channel estate-wide, Regular, and the ring order comes from
the maintenance window — dev Tuesday, staging Wednesday, prod Saturday.**

- Two clocks, one owner each: Kargo owns the socle artifact, Google owns the
  Kubernetes version.
- Rejected alternative — Kargo owning the version: you pin every cluster with
  a `NO_MINOR_UPGRADES` exclusion, drive the version from the pipeline, and
  inherit the full support clock, including shipping a bump before Google
  overrides the exclusion anyway. Window skew gives the same ordering free.
- The window is **required with no default**: a silent default means nobody
  decided when production gets upgraded.
- GKE requires ≥ 48 hours of maintenance availability per 92-day window,
  counting only blocks of four hours or more.

## Metrics

- System metrics: free, not disableable.
- Control plane and kube-state metrics: billed per sample, so off by default.
- What the catalog scrapes: **$0.158 per month per sample/second**.

| Per cluster | Samples/s | Per month |
| --- | --- | --- |
| Unfiltered `kube-prometheus` (Google's figure) | ~900 | $142 |
| Filtered as Google recommends | ~300 | $47 |
| Self-hosted Prometheus + Grafana + disk | n/a | $134 |

**Decision: delegate to Managed Service for Prometheus.**

> **Superseded** by [`docs/monitoring.md`](../monitoring.md) (#43): workload
> metrics go to the socle's in-cluster VictoriaMetrics on every cloud, GKE
> included. The free system metrics below are unaffected. The figures here
> stay as the comparison that decision was made against.

- Crossover is ~850 samples/s per cluster; a filtered cluster sits at a third
  of it.
- Monarch keeps 24 months where a self-hosted Prometheus keeps fifteen days.
- Binding consequence: **the catalog's monitoring module carries a
  samples/second budget**, because cardinality goes straight to the invoice.
- Auto-Monitoring stays off — the feature is free, the samples are not.

## Backup

| | Cost on the reference estate | Covers |
| --- | --- | --- |
| **Velero** | **~$90/month** | Config plus CSI volume snapshots |
| Backup for GKE | $297/month ($9 per namespace-month) | Same, plus managed cross-project restore |

**Decision: Velero by default, Backup for GKE as a priced option.**

- One restore procedure across four clouds.
- Autopilot blocks Velero's node-agent (privileged mode, writable
  `hostPath`), so there is no portable copy of volume data.

## Identity

Autopilot pre-configures Workload Identity Federation and it cannot be
disabled. The pool is `PROJECT_ID.svc.id.goog`.

**Decision: no Google service account, anywhere. A workload that needs Google
Cloud access is granted roles directly on its Kubernetes ServiceAccount, as a
federated principal:**

```text
principal://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/PROJECT_ID.svc.id.goog/subject/ns/NAMESPACE/sa/SERVICE_ACCOUNT
```

- The project **number** in the path, the project **ID** in the pool's name:
  Google's format, and the one the foundations output as
  `workload_identity_principal_prefix` (it carried the ID in both places
  until the GCP parity work fixed it).
- No service account means no key that can leak, no
  `iam.gke.io/gcp-service-account` annotation, and no impersonation grant to
  keep in step with the binding. The pod's token is exchanged for a Google
  one by the metadata server, nothing else.
- Who grants what: of the cluster's workloads, the foundations grant only
  Crossplane's principal, `…/ns/crossplane-system/sa/provider-gcp`; every catalog
  module binds its own principal on its own resources through Crossplane,
  bounded by the roles the client allows
  ([crossplane.md](../catalog/crossplane.md) §2, §3).
- The one place a principal is not enough: a signed URL needs a service
  account to sign with. Velero's CLI downloads (`velero backup logs`) are the
  one feature this costs ([velero.md](../catalog/velero.md) §2, *On GCP*).
- Trap: a principal is built from the project, the namespace and the service
  account name — never the cluster — so two clusters in one project produce
  identical principals. **One socle cluster per project** is the supported
  topology.

## Cost impact

Reference estate, baseline **$1,488/month**.

| | Per month | vs baseline |
| --- | --- | --- |
| Prometheus, filtered to ~300 samples/s per cluster | +$142 | +10% |
| Cloud Logging, 30 GiB per cluster | +$20 | +1% |
| Velero | +$90 | +6% |
| **Recommended position** | **$1,740** | **+17%** |
| *Backup for GKE instead of Velero* | +$297 | +20% |
| *Prometheus unfiltered* | +$426 | +29% |

us-central1 list price, read 8 September 2026.

## Module specification

| Variable | Default | Constraint |
| --- | --- | --- |
| `release_channel` | `"REGULAR"` | `RAPID`, `REGULAR` or `STABLE`; `EXTENDED` rejected |
| `maintenance_window` | **none — required** | ≥ 4h, and ≥ 48h per 92 days |
| `maintenance_exclusions` | `[]` | `NO_UPGRADES` ≤ 90 days, ≤ 3 of that scope |
| `kubernetes_min_version` | `null` | raise-only escape hatch |
| `enable_upgrade_notifications` | `true` | module creates the Pub/Sub topic |
| `logging_components` | system + workloads | system cannot be removed |
| `monitoring_components` | system only | billed components accepted, never defaulted |
| `backup_agent_enabled` | `false` | — |

Absent by decision: the Extended channel, any Workload Identity toggle,
Auto-Monitoring, accelerated patching.

## Sources

Read 8 September 2026. [Release channels][channels] ·
[versioning and support][versioning] · [maintenance windows][maint] ·
[GKE pricing][pricing] · [Observability pricing][obs-pricing] ·
[GKE metrics][gke-metrics] · [Prometheus cost controls][gmp-costs] ·
[Backup for GKE][backup-gke] · [Velero file system backup][velero-fsb] ·
[Workload Identity Federation][wif].

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
