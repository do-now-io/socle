# Observing Google Cloud resources outside the cluster

Managed services around a cluster — databases, buckets, queues — and the cost
data that describes all of it, read from a central observability cluster.
In-cluster metrics are in [managed scope](managed-scope.md).

| Question | Position |
| --- | --- |
| Google Cloud service metrics | Read from the Monitoring API, every 300 s |
| Reading cluster metrics through the same API | Refused — 100× the cost |
| Direct exporters (database engines) | Catalog option, for signal the API lacks |
| Alerting | Ours — one Alertmanager for four clouds |
| Cloud Monitoring alert policies | Refused — billable from September 2027 |
| Cost attribution source | Detailed usage cost export to BigQuery |
| GKE cost allocation | On, from day one |
| FOCUS export | The target, once it leaves Preview |
| Quota metrics | In the standard perimeter |
| Recommender | A monthly report, not a signal |

## What it costs to pull metrics out

Ingestion is free — Google Cloud service metrics land in Cloud Monitoring at
no cost. **Reading them out is billed, and the meter changed on 2 October
2025: $0.50 per million time series returned**, one million free per month.
Any cost model that counts API calls is out of date.

A perimeter of ~800 service time series — two Cloud SQL instances, a
Memorystore, buckets, topics, load balancers, NAT and quotas:

| Scrape interval | Per month |
| --- | --- |
| 60 s | $17.02 |
| **300 s** | **$3.00** |
| 900 s | $0.67 |

**Decision: scrape at 300 seconds with `stackdriver_exporter` in the central
cluster.** Nothing a managed database does needs one-minute resolution from a
supervision plane, and 60 seconds costs five times more.

**The mistake to avoid:** pointing the same exporter at cluster metrics stored
in Monarch — 20,000 series at 60 s is **$438/month**. In-cluster metrics stay
on the in-cluster path.

Cloud Monitoring's own alert policies are free today but **billable from 1
September 2027**, and would put one cloud of four on a separate alerting path.
Alerting stays ours.

## Billing export as the cost attribution source

**Decision: the detailed usage cost export, in the client's own project, with
GKE cost allocation on.**

- **Cost:** effectively zero. The export is free, and a small estate is
  megabytes a month against 10 GiB of free BigQuery storage.
- **Latency:** hours, up to five days for the initial backfill. Fine monthly,
  useless as a live signal.
- **Granularity:** resource level, plus namespace and workload once cost
  allocation is on.
- **Auditable:** the dataset is in the client's project and the client can run
  the same query. Google publishes the query that reproduces an invoice total
  but guarantees no match — so "reproducible from their own data", not
  "certified".

GKE cost allocation appears only in the detailed export, takes three days to
show up and **does not backfill**, which is why it belongs in the module
rather than in an onboarding checklist.

**The defect:** the export cannot be enabled by API. No Terraform resource, no
`gcloud` command, no public endpoint — configuring the destination dataset is
a Console action. The module creates the dataset; a human links the billing
account. It is the one documented breach of the checklist's "single apply, no
out-of-band step" rule.

FOCUS is the export that would give one schema across four clouds, and Google
even absorbs its storage — but it is Preview, so it is the target rather than
the default.

## Read-only service coverage

Free to ingest, and the column that decides is whether the API is the only
source.

| Service | Direct alternative | Position |
| --- | --- | --- |
| Cloud SQL, Memorystore | `postgres_exporter`, `redis_exporter` for query-level detail | Standard perimeter; exporter is a catalog option |
| Cloud Storage, Pub/Sub | none | Standard perimeter, API only — Pub/Sub backlog age is the alert that matters |
| Load balancers, Cloud NAT | none | Standard perimeter |
| Quotas | none | Standard perimeter |

**Quota metrics earn the API read on their own:** usage against limit is a
genuine leading indicator of an outage, and it is one alert rule per quota
that matters.

**Recommender stays out of the metrics pipeline.** Recommendations are free
and the API is open, but its BigQuery export requires a paid support package
and API quotas depend on that contract. More fundamentally a recommendation is
not an event — it becomes a monthly report next to the cost data.

## Cost impact

| | Per month |
| --- | --- |
| Monitoring read API, ~800 series at 300 s | +$3.00 |
| Billing export, quota and service metrics | $0 |
| **Total** | **+$3.00 (+0.2%)** |
| *The same perimeter at 60 s* | +$17 |
| *Cluster metrics read through the API by mistake* | +$438 |

us-central1 list price, read 8 September 2026. Re-price before quoting.

## Module specification

Most of this lands in the central cluster and the catalog. What the module
owes it:

| Variable | Default | Constraint |
| --- | --- | --- |
| `cost_allocation_enabled` | `true` | no backfill, so it must be true from day one |
| `billing_export_dataset_id` | `null` | when set, creates the dataset; linking stays manual |
| `observability_reader_members` | `[]` | federated principals, never a key |

Absent by decision: any alert policy, dashboard, uptime check or metrics
scope. Alerting and dashboards are catalog objects so four clouds share one
definition.

## Known gaps

- **Which side pays the read charge is not documented.** At $3 a month it
  changes nothing; across many client projects it decides who carries the
  line. `time_series_billed_for_queries_count` is the metric that answers it.
- **The 800-series perimeter is an estimate, not an inventory.** The per-series
  unit cost is the reliable part.
- **The invoice reconciliation claim is weaker than it sounds.** Reconcile one
  real month before the figure becomes contractual.

## Sources

Read 8 September 2026. [Observability pricing][obs-pricing] (read API pricing,
non-chargeable metrics, alerting policy pricing from September 2027) ·
[quota metrics][quota-metrics] · [billing export to BigQuery][billing-export]
and [its tables][billing-tables] · [FOCUS export][focus] · [example billing
queries][bq-examples] · [GKE cost allocation][cost-alloc] · [BigQuery
pricing][bq-pricing] · [Recommender pricing][recommender] · [no Terraform
resource for the billing export][tf-issue].

[obs-pricing]: https://cloud.google.com/stackdriver/pricing
[quota-metrics]: https://cloud.google.com/monitoring/alerts/using-quota-metrics
[billing-export]: https://cloud.google.com/billing/docs/how-to/export-data-bigquery
[billing-tables]: https://cloud.google.com/billing/docs/how-to/export-data-bigquery-tables
[focus]: https://cloud.google.com/billing/docs/how-to/export-data-bigquery-tables/focus-export
[bq-examples]: https://cloud.google.com/billing/docs/how-to/bq-examples
[cost-alloc]: https://cloud.google.com/kubernetes-engine/docs/how-to/cost-allocations
[bq-pricing]: https://cloud.google.com/bigquery/pricing
[recommender]: https://cloud.google.com/recommender/pricing
[tf-issue]: https://github.com/hashicorp/terraform-provider-google/issues/4848
