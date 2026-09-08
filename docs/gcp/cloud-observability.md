# Observing Google Cloud resources outside the cluster

Managed services around a cluster and the cost data describing it, read from a
central observability cluster. In-cluster metrics: see
[managed scope](managed-scope.md).

| Question | Position |
| --- | --- |
| Google Cloud service metrics | Monitoring API, every 300 s |
| Cluster metrics through that API | Refused — 100× the cost |
| Database engine exporters | Catalog option, for signal the API lacks |
| Alerting | Ours — one Alertmanager for four clouds |
| Cloud Monitoring alert policies | Refused — becomes billable |
| Cost attribution | Detailed usage cost export to BigQuery |
| GKE cost allocation | On, from day one |
| FOCUS export | The target, once it leaves Preview |
| Quota metrics | In the standard perimeter |
| Recommender | Monthly report, not a signal |

## Pulling metrics out

- Ingestion is **free** — Google Cloud service metrics land in Cloud
  Monitoring at no cost.
- Reading them out is billed **per time series returned**, since the meter
  changed in October 2025. Any cost model counting API calls is out of date.

A perimeter of ~800 service time series — two Cloud SQL instances, a
Memorystore, buckets, topics, load balancers, NAT, quotas:

| Scrape interval | Per month |
| --- | --- |
| 60 s | $17.02 |
| **300 s** | **$3.00** |
| 900 s | $0.67 |

**Decision: 300 seconds, with `stackdriver_exporter` in the central cluster.**

- Nothing a managed database does needs one-minute resolution from a
  supervision plane, and 60 s costs five times more.
- **The mistake to avoid:** pointing the same exporter at cluster metrics —
  20,000 series at 60 s is **$438/month**. In-cluster metrics stay on the
  in-cluster path.
- Cloud Monitoring alert policies are free today, **billable from September
  2027**, and would split alerting across clouds. Alerting stays ours.

## Cost attribution

**Decision: the detailed usage cost export, in the client's own project, with
GKE cost allocation on.**

| | |
| --- | --- |
| Cost | Effectively zero — export is free, a small estate is megabytes |
| Latency | Hours, up to five days to backfill. Monthly, not live |
| Granularity | Resource level, plus namespace and workload |
| Auditable | The client's own dataset, so they can run the same query |

- Cost allocation appears only in the detailed export, takes three days to
  show up and **does not backfill** — hence a module default, not an
  onboarding step.
- Google publishes the query that reproduces an invoice total but guarantees
  no match: reproducible from the client's data, not certified.
- **The defect:** the export cannot be enabled by API — no Terraform
  resource, no `gcloud`, no endpoint. The module creates the dataset; a human
  links the billing account. The one breach of "single apply, no out-of-band
  step".
- FOCUS would give one schema across four clouds and Google absorbs its
  storage, but it is Preview: target, not default.

## Service coverage

| Service | Direct alternative | Position |
| --- | --- | --- |
| Cloud SQL, Memorystore | `postgres_exporter`, `redis_exporter` | Standard perimeter; exporter is a catalog option |
| Cloud Storage, Pub/Sub | none | Standard perimeter — Pub/Sub backlog age is the alert that matters |
| Load balancers, Cloud NAT | none | Standard perimeter |
| Quotas | none | Standard perimeter |

- Quota metrics justify the API read on their own: usage against limit is a
  leading indicator of an outage.
- Recommender stays out of the pipeline — its BigQuery export needs a paid
  support package, and a recommendation is not an event.

## Cost impact

| | Per month |
| --- | --- |
| Monitoring read API, ~800 series at 300 s | +$3.00 |
| Billing export, quota and service metrics | $0 |
| **Total** | **+$3.00 (+0.2%)** |
| *Same perimeter at 60 s* | +$17 |
| *Cluster metrics through the API by mistake* | +$438 |

us-central1 list price, read 8 September 2026. Re-price before quoting.

## Module specification

Most of this lands in the central cluster and the catalog. What the module
owes it:

| Variable | Default | Constraint |
| --- | --- | --- |
| `cost_allocation_enabled` | `true` | no backfill, so true from day one |
| `billing_export_dataset_id` | `null` | creates the dataset; linking stays manual |
| `observability_reader_members` | `[]` | federated principals, never a key |

Absent by decision: alert policies, dashboards, uptime checks, metrics
scopes — catalog objects, so four clouds share one definition.

## Sources

Read 8 September 2026. [Observability pricing][obs-pricing] (read API,
non-chargeable metrics, alerting policy pricing) · [quota
metrics][quota-metrics] · [billing export][billing-export] and
[its tables][billing-tables] · [FOCUS export][focus] · [example
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
