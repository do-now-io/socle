# Observing Google Cloud resources outside the cluster

Managed services around a cluster — databases, buckets, queues — and the cost
data that describes all of it. In-cluster metrics are in
[managed scope](managed-scope.md); this document is about everything a cluster
depends on but does not contain, read from a central observability cluster
that holds no Google Cloud resources of its own.

| Question | Position | Where it lands |
| --- | --- | --- |
| Google Cloud service metrics | Read from the Monitoring API | central cluster, not the module |
| Scrape interval | 300 seconds | one line of exporter config, and the whole cost question |
| Reading in-cluster metrics through the same API | Refused — three orders of magnitude more expensive | — |
| Direct exporters (database engines) | Catalog option, for signal the API lacks | catalog |
| Alerting | Ours — one Alertmanager for four clouds | catalog |
| Cloud Monitoring alert policies | Refused — priced from 1 September 2027, and per-cloud | — |
| Cost attribution source | Detailed usage cost export to BigQuery | dataset by the module, export by hand |
| GKE cost allocation | On | `cost_allocation_enabled`, default `true` |
| FOCUS export | Catalog option today, the target once GA | — |
| Quota metrics | In the standard perimeter | central cluster |
| Recommender | Catalog option — a monthly report, not a signal | — |

## 1. What it costs to pull Cloud Monitoring out

Two facts set the whole answer.

**Ingestion is already paid for, and it is free.** "Metric data from Google
Cloud and Knative isn't chargeable" — Cloud SQL, Cloud Storage, Pub/Sub,
Memorystore and the quota metrics all land in Cloud Monitoring at no cost,
whether or not anyone looks at them.

**Reading them out is what costs, and the meter changed recently.** Since
2 October 2025, Monitoring read API calls are billed **$0.50 per million time
series returned**, with one million free per billing account per month —
before that date it was one unit per call, which is why older cost models are
wrong. Console reads are free; the pricing page names Grafana explicitly as a
third-party tool that issues charged reads. So the unit that matters is not the
call, it is the time series, multiplied by how often you ask.

A perimeter of roughly 800 Google Cloud time series — two Cloud SQL instances,
a Memorystore, a handful of buckets, ten topics and subscriptions, the load
balancers, NAT and quota metrics — costs this much to scrape continuously:

| Scrape interval | Time series returned per month | Per month |
| --- | --- | --- |
| 60 s | 35.0 M | $17.02 |
| **300 s** | **7.0 M** | **$3.00** |
| 900 s | 2.3 M | $0.67 |

**The concern in the ticket is real but small at this scale, provided two rules
hold.** Scrape at 300 seconds: nothing a managed database or a bucket does
needs one-minute resolution from a supervision plane, and 60 seconds costs five
times as much for it. And keep the perimeter to Google Cloud service metrics:
pointing the same exporter at cluster metrics stored in Monarch — call it
20,000 series at 60 seconds — is **876 million series a month, $438**. That is
the mistake this document exists to prevent, and it is why in-cluster metrics
stay on the in-cluster path.

**The ways to get the data, and what each is worth:**

| Path | Read charge | Worth it |
| --- | --- | --- |
| `stackdriver_exporter` in the central cluster | yes, per series scraped | **Yes.** One deployment, every project, Prometheus-native. ~$10/month of Pod requests, shared across all clients |
| OpenTelemetry Collector, `googlecloudmonitoring` receiver | identical — same API | Equivalent; choose on operational grounds, not cost |
| Grafana's Cloud Monitoring data source, queried on demand | yes, per dashboard view | As a complement. Cost follows attention rather than time, but there is no history in our store and nothing to alert on |
| Direct exporters against the engine (`postgres_exporter`, `redis_exporter`) | none | **For signal, not for cost.** Query-level database metrics do not exist in Cloud Monitoring. Needs a database user and private connectivity, so: catalog option |
| Cloud Storage, Pub/Sub | — | No direct path exists. The API is the only source |
| Cloud Monitoring alert policies | free today | **No.** Priced from **1 September 2027** at $0.35 per metric reference per month plus $0.50 per million points evaluated, and it would put one of four clouds on a different alerting path |

## 2. Billing export to BigQuery as the cost attribution source

**Confirmed as the reference source, with one honest defect.**

Four exports exist. **Standard usage cost** is SKU and project level.
**Detailed usage cost** adds resource-level rows and is the only one that
carries GKE cost allocation labels. **Pricing data** carries the rates.
**FOCUS usage cost** is in **Preview**: an immutable, Google-provided dataset
normalised to the FinOps Open Cost and Usage Specification, whose storage
Google pays for over the last two years.

| | |
| --- | --- |
| **Cost** | The export is free. A small estate's detailed export is megabytes a month, against 10 GiB of free BigQuery storage and 1 TiB of free queries; storage past that is $0.023/GiB-month and queries $6.25/TiB. **Effectively zero.** |
| **Latency** | Hours, not minutes. Up to five days for the initial backfill, up to 48 hours for pricing data. Fine for monthly attribution, useless as a live signal |
| **Granularity** | Resource level in the detailed export, and per namespace, workload and Pod label once GKE cost allocation is on |
| **Auditable by the client** | The dataset lives in the client's own project, so the client can run the same query. The documentation's own example reconstructs the invoice total from `invoice.month` with `SUM(cost)` plus credits — but it states no guarantee that the totals match, and offers no audit procedure. "Auditable" here means reproducible from the client's own data, not certified |

**GKE cost allocation goes on.** It adds `k8s-namespace`,
`goog-k8s-cluster-name`, `k8s-workload-type`, `k8s-workload-name` and Pod
labels to the billing rows, works on Autopilot, and changes no price. Three
caveats worth knowing before promising a number: it appears **only** in the
detailed export, it takes **up to three days** to show up, and it does **not
backfill** — so it has to be enabled the day a cluster is created, which is
exactly why it belongs in the module rather than in an onboarding checklist.

**The defect: the export cannot be enabled by API.** There is no Terraform
resource and no `gcloud` command, because there is no public API — configuring
the destination dataset is a Cloud Console action. The module can create the
dataset, its location and its IAM; **linking the billing account to it is a
manual step**, and it is the one place where the
[module checklist](../standards/opentofu-module.md)'s "single apply, no
out-of-band step" rule cannot be met. Stated here rather than discovered later.

**FOCUS is the target, not the default.** It is the only export that yields one
schema across clouds, which is precisely what a four-cloud offering needs, and
Google even absorbs its storage. It is Preview, so the default stays the
detailed export, and this decision gets revisited when FOCUS goes GA.

## 3. Read-only service coverage

Everything below is free to ingest and costs only what section 1 describes.
The column that matters is whether the API is the *only* source.

| Service | In Cloud Monitoring | Direct alternative | Position |
| --- | --- | --- | --- |
| Cloud SQL | CPU, memory, disk, connections, replication lag | `postgres_exporter` / `mysqld_exporter` for query-level detail | Standard perimeter; exporter is a catalog option |
| Memorystore | Hit rate, memory, evictions, connections | `redis_exporter` | Same |
| Cloud Storage | Request counts, sizes, object counts | none | Standard perimeter, API only |
| Pub/Sub | Backlog size, oldest unacked message age, delivery | none | Standard perimeter, API only — and the backlog age is the alert that matters |
| Load balancers, Cloud NAT | Requests, latency, port exhaustion, dropped packets | none | Standard perimeter |
| Quotas | `serviceruntime.googleapis.com/quota/*` on the Consumer Quota resource | none | Standard perimeter — see below |

## 4. Recommender and quotas

**Quota metrics belong in the standard perimeter**, and they are the strongest
argument in this document for reading the API at all: allocation usage, rate
usage, the limit itself and the exceeded-error count are all published under the
Consumer Quota resource type, and the ratio of usage to limit is a genuine
leading indicator of an outage. It is one alert rule per quota that matters —
addresses, NAT ports, API rates — expressed the same way the rest of our
alerting is.

**Recommender does not belong in the metrics pipeline.** Most recommendations
and insights are generated free for all customers, and the API is open to
everyone, but two things disqualify it as a supervision signal. Its **BigQuery
export requires a paid support package** (Standard, Enhanced or Premium), and
API quotas differ depending on whether a support package was bought — a
dependency on a commercial agreement we do not control. More fundamentally, a
recommendation is not an event: it is a periodic finding about waste, right-
sizing and idle resources.

So: pull it on a schedule through the API, into a **monthly report** alongside
the cost attribution data, and keep it out of the alerting path. Firewall
Insights is the one premium recommender that costs extra, and it is refused by
default on that basis.

## Cost impact on the reference estate

Same estate as the [cluster mode research](README.md), baseline
**$1,488/month**, plus the managed services described in section 1.

| | Per month | vs baseline |
| --- | --- | --- |
| Monitoring read API, ~800 series at 300 s | +$3.00 | +0.2% |
| Billing export, detailed, with GKE cost allocation | $0 | — |
| Quota and service metric ingestion | $0 | — |
| **Total** | **+$3.00** | **+0.2%** |
| *The same perimeter at a 60-second interval* | +$17.02 | +1% |
| *Cluster metrics read through the same API by mistake* | +$438 | +29% |
| *Cloud Monitoring alert policies, 40 references, from Sept 2027* | +$14 | +1% |

The `stackdriver_exporter` itself is about $10/month of Autopilot Pod requests
in the central cluster, shared across every client rather than charged to one.

Rates, us-central1 list price read 8 September 2026: Monitoring read API
$0.50 per million time series returned with 1 million free per billing account
per month; Google Cloud metric ingestion free; BigQuery on-demand queries free
to 1 TiB then $6.25/TiB, active logical storage $0.023/GiB-month with 10 GiB
free; alerting policies $0.35 per metric reference per month and $0.50 per
million points evaluated **from 1 September 2027**. Re-price before quoting.

## Module specification

Most of this document lands in the central cluster and the catalog, not in the
foundations module. What the module owes it:

| Variable | Type | Default | Constraint |
| --- | --- | --- | --- |
| `cost_allocation_enabled` | `bool` | `true` | `cost_management_config` on the cluster; no backfill, so it must be true from day one |
| `billing_export_dataset` | `string` | `null` | when set, the module creates the BigQuery dataset and its IAM; linking the billing account stays manual |
| `observability_reader_members` | `list(string)` | `[]` | principals granted `roles/monitoring.viewer` on the project — the central cluster's identity, federated, never a key |

Absent by decision: any Cloud Monitoring alert policy, dashboard or uptime
check, any Recommender configuration, and any metrics scope. Alerting and
dashboards are catalog objects so that four clouds share one definition.

Outputs: the dataset reference and the reader role bindings, so the central
cluster's configuration can be generated rather than hand-written.

## Known gaps

- **Which side pays the read charge is not documented plainly.** The pricing
  page says reads are billed per time series returned, but not whether the
  charge follows the project issuing the request or the project owning the
  metrics. At $3 a month it changes nothing; at scale across many client
  projects it decides who carries the line. It needs confirming against a real
  bill, and `time_series_billed_for_queries_count` is the metric that answers
  it.
- **The 800-series perimeter is an estimate, not an inventory.** It is built
  from a plausible set of managed services, not measured on a client estate.
  The per-series unit cost is the reliable part.
- **The invoice reconciliation claim is weaker than it sounds.** Google
  publishes the query that reproduces an invoice total but promises nothing
  about it matching. Anyone relying on the export as a contractual figure
  should reconcile one real month before it becomes one.
- **FOCUS being Preview blocks the multi-cloud answer.** Until it is GA, cost
  data has to be normalised by us, per cloud — which is work the FOCUS export
  is designed to delete.
- **The manual billing export step has no workaround.** Not a documentation
  gap; there is no API. It has to be in the onboarding runbook, and it will
  fail silently for a client who skips it, because nothing else breaks.

## Sources

Read 8 September 2026. [Google Cloud Observability pricing][obs-pricing]
(read API pricing, non-chargeable metrics, alerting policy pricing from
September 2027) · [Cloud Monitoring API pricing][api-pricing] · [chart and
monitor quota metrics][quota-metrics] · [Cloud Billing export to
BigQuery][billing-export] and [its tables][billing-tables] ·
[FOCUS export structure][focus] · [example billing queries][bq-examples] ·
[GKE cost allocation][cost-alloc] · [BigQuery pricing][bq-pricing] ·
[Recommender pricing][recommender] · [`google_container_cluster`][tf-cluster] ·
[no Terraform resource for the billing export][tf-issue].

[obs-pricing]: https://cloud.google.com/stackdriver/pricing
[api-pricing]: https://cloud.google.com/stackdriver/pricing#monitoring-api
[quota-metrics]: https://cloud.google.com/monitoring/alerts/using-quota-metrics
[billing-export]: https://cloud.google.com/billing/docs/how-to/export-data-bigquery
[billing-tables]: https://cloud.google.com/billing/docs/how-to/export-data-bigquery-tables
[focus]: https://cloud.google.com/billing/docs/how-to/export-data-bigquery-tables/focus-export
[bq-examples]: https://cloud.google.com/billing/docs/how-to/bq-examples
[cost-alloc]: https://cloud.google.com/kubernetes-engine/docs/how-to/cost-allocations
[bq-pricing]: https://cloud.google.com/bigquery/pricing
[recommender]: https://cloud.google.com/recommender/pricing
[tf-cluster]: https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/container_cluster
[tf-issue]: https://github.com/hashicorp/terraform-provider-google/issues/4848
