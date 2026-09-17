# Observing Azure resources outside the cluster

Managed services around a cluster, cost data, and quota signals — read into
the client's own observability cluster. In-cluster metrics: see
[managed scope](managed-scope.md).

| Question | Position |
| --- | --- |
| Azure service metrics | Metrics REST API (`metrics:getBatch`), every 300s |
| Cluster metrics through that path | Refused — wrong path entirely |
| Log Analytics / Basic Logs | Refused as the ingestion path — metrics never touch it |
| Database/cache exporters | Catalog option, for signal the API lacks |
| Alerting | Ours — one Alertmanager for four clouds |
| Cost attribution | Cost Management Exports to the client's own storage account |
| Cost Management Query/Details API | Refused as the audit source |
| Quota metrics | `Microsoft.Quota` usages API, standard perimeter |

## Pulling metrics out

**Decision: 300 seconds, via `metrics:getBatch`.**

- Platform metrics ingest for free and are retained 90 days automatically —
  nothing to configure, no workspace involved.
- Reading costs $0.01 per 1,000 API calls. `metrics:getBatch` covers up to
  50 resources per call within one metric namespace, so a modest estate
  turns into a handful of calls per scrape rather than one per resource —
  the same batching logic that keeps this path cheap everywhere else.
- **The one thing to avoid: Log Analytics.** Nothing about this perimeter
  needs it — metrics never touch it, so none of Log Analytics' cost
  drivers apply: Analytics Logs runs $2.76/GB ingestion plus $2.30/GB
  scanned per query; even Basic Logs, the cheap tier, is $0.625/GB
  ingestion plus $0.00625/GB scanned. Basic Logs stays a catalog option for
  a client who genuinely needs a log signal later — cheaper than Analytics
  Logs, but still a real, ongoing cost, unlike metrics.
- Diagnostic logs sent anywhere other than a Log Analytics workspace
  (Event Hub, a storage account) are billed for processing regardless —
  another reason this perimeter never reaches for them by default.

Illustrative reference perimeter — four service namespaces (SQL, Storage,
Service Bus, Redis) plus one quota-API pass, ~15 resources:

| Scrape interval | Per month |
| --- | --- |
| 60 s | $2.16 |
| **300 s** | **$0.43** |
| 900 s | $0.14 |
| *Same perimeter shipped to Basic Logs instead (~30 GB/month)* | $18.75 |
| *Same perimeter shipped to Analytics Logs instead* | $82.80 |

The metrics path is a rounding error either way — the real cost this
decision avoids isn't the read, it's routing any of it through Log
Analytics in the first place.

## Cost attribution

**Decision: Cost Management Exports, delivered to the client's own storage
account.**

- Free to generate — CSV or Parquet, on a schedule, written straight to the
  client's own storage account. The only cost is the storage itself,
  which is small.
- Auditable by construction: the client's own dataset, queryable however
  they choose — not a number Do Now hands them.
- The Cost Details/Query API is refused as the audit source: free to call,
  but rate-limited by query processing units, capped at one month of data
  per request, and refreshed roughly every four hours — built for periodic
  batch pulls, not a live source. It's also Do Now calling it on the
  client's behalf rather than the client's own dataset — the same defect
  as relying on it for a figure a client needs to independently verify.

## Service coverage

Same criterion as elsewhere: **systematic** (common enough across clients
to build once) **and** **actionable** (the metric drives a real alert, not
just a number to look at).

| Service | Key metrics | Position |
| --- | --- | --- |
| Azure SQL Database | CPU/DTU or vCore %, deadlocks, storage % | Standard perimeter |
| Storage Account | Availability, latency, capacity | Standard perimeter |
| Service Bus | Active message count, dead-letter message count | Standard perimeter — dead-letter growth is the alert that matters |
| Azure Cache for Redis | Server load %, used memory %, connected clients | Standard perimeter; `redis_exporter` against the endpoint is a catalog option for signal the platform metrics lack |

- Deadlocks and dead-letter count are the clean case for the criterion:
  present on essentially every client, and each one is a real incident, not
  a number to glance at.
- Server load past 80% and used memory past 85% are Microsoft's own
  documented thresholds before failovers and evictions start — not
  arbitrary values chosen here.

## Quotas & limits

**Decision: `Microsoft.Quota` usages API, same pipeline, 300s.**

- Free, and covers Compute (vCPU per VM family per region) and Network
  (public IPs, NSGs, NAT Gateways, load balancers, private endpoints)
  directly — current usage against the limit, not just the limit itself.
- Default set: vCPU per VM family per region, public IPs, NSGs, NAT
  Gateways — each a known way a cluster silently stops scaling or
  provisioning before anyone notices.

## Module specification

| Variable | Default | Constraint |
| --- | --- | --- |
| `metrics_export_enabled` | `true` | — |
| `metrics_scrape_interval_seconds` | `300` | — |
| `quota_monitoring_enabled` | `true` | — |
| `cost_export_enabled` | `true` | scheduled, to the client's own storage account |
| `log_analytics_workspace_id` | `null` | absent by default — only set if a client needs a Basic Logs signal later |

Absent by decision: any Analytics Logs or diagnostic-settings-to-Log-Analytics
variable, any Cost Details/Query API credential — catalog surface where it
exists at all, not module defaults.

## Sources

Read September 2026, France Central pricing.

[Azure Monitor cost and usage][cost-usage] ·
[Azure Monitor pricing][monitor-pricing] ·
[Metrics Batch API][metrics-batch] ·
[Cost Management Exports][cost-exports] ·
[Generate Cost Details Report API][cost-details] ·
[Quotas overview][quotas-overview] · [Quota usages API][quota-usages] ·
[Service Bus monitoring reference][sb-monitor] ·
[Azure SQL Database monitoring][sql-monitor] ·
[Azure Cache for Redis best practices][redis-monitor] ·
[Azure Retail Prices API][retail-prices].

[cost-usage]: https://learn.microsoft.com/en-us/azure/azure-monitor/fundamentals/cost-usage
[monitor-pricing]: https://azure.microsoft.com/en-us/pricing/details/monitor/
[metrics-batch]: https://learn.microsoft.com/en-us/rest/api/monitor/metrics-batch/batch?view=rest-monitor-2023-10-01
[cost-exports]: https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/tutorial-improved-exports
[cost-details]: https://learn.microsoft.com/en-us/rest/api/cost-management/generate-cost-details-report/create-operation
[quotas-overview]: https://learn.microsoft.com/en-us/azure/quotas/quotas-overview
[quota-usages]: https://learn.microsoft.com/en-us/rest/api/quota/usages/list
[sb-monitor]: https://learn.microsoft.com/en-us/azure/service-bus-messaging/monitor-service-bus-reference
[sql-monitor]: https://learn.microsoft.com/en-us/azure/azure-sql/database/monitoring-metrics-alerts
[redis-monitor]: https://learn.microsoft.com/en-us/azure/azure-cache-for-redis/cache-best-practices-server-load
[retail-prices]: https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices
