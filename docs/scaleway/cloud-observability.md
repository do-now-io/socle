# Observing Scaleway resources outside the cluster

Managed services around a cluster and the cost data describing it, read from
a central observability cluster. In-cluster metrics: see
[capabilities](kapsule-capabilities.md#observability).

| Question | Position |
| --- | --- |
| Scaleway service metrics | Cockpit's `/federate` endpoint, every 300 s |
| Scraping the Scaleway APIs directly | Refused — Cockpit already holds the data, free |
| Pushing workload metrics into Cockpit | Refused — billed per sample |
| Alerting | Ours — one Alertmanager for four clouds |
| Scaleway alert manager | Refused — splits alerting, and Grafana's own is unsupported |
| Cost attribution | Consumption API, one Project per environment |
| Per-namespace cost | Does not exist — OpenCost in the catalog if a client asks |
| Quotas | Raised at onboarding, then watched |
| Audit Trail | Not in Cockpit — out of the metrics path |

## Reading Scaleway's data

Cockpit is Grafana over Mimir, Loki and Tempo. **Scaleway's own metrics and
logs land there for free**, with a free dashboard per product, retained 31
days for metrics and 7 for logs.

Two ways out of it, and neither is the Scaleway product APIs:

| | How | Cost |
| --- | --- | --- |
| **`/federate`** | Prometheus federation against the data source, `match[]` selectors, token with `query` | **Free during beta, billable after** |
| Query endpoints | Mimir `/prometheus/api/v1/query_range`, `series`, `labels`; Loki equivalents | same token |
| Data exports | push to Datadog or an OTLP endpoint, per data source | free during beta, then by volume |

**Decision: federate from the central observability cluster, every 300
seconds, with `match[]` narrowed to the products in the perimeter.**

- It is the same shape as the AWS and GCP positions — one cadence across the
  supervision plane, not a per-cloud tuning exercise — and here it costs
  nothing to read today.
- **The cost to plan for is the end of the beta.** Scaleway states plainly
  that `/federate` will be billed afterwards and publishes no rate. This is
  the one figure in this document that has to be re-read before a client
  signs.
- Data exports are refused as the mechanism: per data source, so per region
  and per Project, and they only reach Datadog or an OTLP endpoint. A pull
  the central cluster controls beats a push Scaleway controls.
- **The mistake to avoid** is the mirror of GCP's: not reading too much, but
  *pushing*. Sending workload metrics into Cockpit is billed per sample, at
  ~2.5× GKE's rate — argued in
  [capabilities](kapsule-capabilities.md#observability). Workload metrics
  stay in the socle's Prometheus.

### What is actually available

| Service | Metrics | Logs |
| --- | --- | --- |
| Managed Database PostgreSQL / MySQL | yes | yes |
| Managed Redis, Managed MongoDB | yes | Redis only |
| Load Balancers, Public Gateways | yes | yes |
| Object Storage | yes | yes |
| Block Storage | yes | no |
| Serverless Containers, Functions, Jobs | yes | yes |
| Queues, Topics and Events, NATS | yes | no |
| Secret Manager, VPC, InterLink, Edge Services | yes | Edge Services only |
| **Container Registry** | **no** | **no** |
| **Domains and DNS** | **no** | **no** |
| **IAM, Key Manager** | **no** | **no** |
| **Audit Trail** | **no** | **no** |

- Coverage of the services a client actually runs is good: every managed
  database, both storage products, the whole serverless range and all the
  network path.
- **Container Registry is the gap that matters**, because the socle pulls
  its own artifacts through it. No metric, no log, so registry availability
  is observed from the consumer side — Flux's own reconciliation failures —
  not from the registry.
- Database engine exporters stay a catalog option, for the signal the
  managed metrics lack, exactly as on GCP.

## Alerting

**Ours.** Scaleway ships a regionalised alert manager with preconfigured
alerts per product and email or webhook contacts, and it is refused as the
default for the reason alerting is refused on every cloud: four clouds, one
Alertmanager, one routing tree, one on-call.

Two Scaleway-specific reasons on top:

- It is **regionalised and per data source** — an estate in two regions
  configures alerting twice.
- Scaleway **does not support Grafana's own alert manager** in its Grafana;
  you must select "Scaleway Alerting". So the Grafana that comes with Cockpit
  cannot be driven the way the socle's Grafana is.

Limits if it were ever used: 20 rules per group, 70 rule groups per Project,
15-second minimum evaluation interval, 1-hour maximum range in a rule query.

## Cost attribution

**Decision: the Billing API's consumption endpoint, read per Project, with
one Project per environment.**

| | |
| --- | --- |
| Cost | Free |
| Granularity | One line per resource — `resource_name`, `product_name`, `sku`, `billed_quantity`, `unit`, `value` |
| Scope filter | Organization **or** Project, plus category |
| Period | `YYYY-MM`. **Monthly. There is no daily breakdown** |
| Auditable | The client reads the same endpoint with `BillingReadOnly` and gets the same lines |

- Resource-level lines make the "% of the cloud bill" reproducible, which is
  what the offer needs: the client can re-run the query against their own
  Organization and reconcile it with the invoice, which is downloadable
  through the same API.
- **There are no tags and no labels on consumption.** The Project is the only
  attribution axis that exists. That is why the module takes a required
  `project_id` and why one environment means one Project — the same
  conclusion the IAM work reaches from the other direction, in
  [managed scope](managed-scope.md#iam).
- **Per-namespace cost does not exist.** GKE cost allocation has no
  equivalent, so in-cluster showback means OpenCost in the catalog, priced
  as its own line, not a provider feature to switch on.
- Page size is capped at 100, so a real estate pages. Not a problem, worth
  knowing before writing the collector.
- Billing alerts — a budget in euros and a threshold, by email, SMS or
  webhook — are the one Scaleway-side alert kept, because the signal only
  exists on Scaleway's side and it fires monthly, not per incident.

## Quotas

Scaleway quotas are per instance type and low enough to block a first
deployment. **The reference estate does not fit in a default account.**

| Quota | Default, identity validated | Estate needs |
| --- | --- | --- |
| `COMPUTE3-X8C-16G` | **not published** | **4 in production** |
| `POP2-HC-8C-16G`, the shape it replaces | **2** | 4 |
| `POP2-HC-4C-8G` | 4 | 2 |
| Kapsule clusters | 40 | 3 |
| Kapsule with a dedicated control plane 4 or 8 | **4** | 1 per production cluster |
| Load Balancers | 50 | 3 |
| Public Gateways per Organization | 50 | 5 |
| Private Networks attached to Public Gateways | 10 | 1 |
| Private Networks per Organization | 255 | 3 |

- **Production's node type is the blocker.** The quota table has not been
  updated for the Zen 5 generation, so `COMPUTE3-X` has no published figure
  at all — but the shape it replaces is capped at two against an estate that
  wants four, and there is no reason to expect better. Read the real number
  from the console before the first apply; the module cannot raise a quota.
- **The dedicated control plane quota caps the offer at four production
  clusters** per Organization before another ticket. Worth knowing when
  pricing a client with many production environments.
- Identity validation is itself a prerequisite: without it, most useful
  instance types have no quota at all.
- Cockpit's own ingestion limits — Mimir 25,000 samples/s and 1M active
  series per data source, Loki 4 MB/s — do not bind while workload metrics
  stay out of Cockpit.

**Position: quota raises are an onboarding checklist item, and quota
consumption is not a metric to watch.** Scaleway exposes no quota metric in
Cockpit, so unlike GCP there is nothing to alert on. The control is the
checklist, and the symptom is a failed apply.

## Cost impact

| | Per month |
| --- | --- |
| Cockpit, Scaleway data and dashboards | €0 |
| `/federate`, ~800 series at 300 s | **€0 today, unpriced after beta** |
| Billing API, quota checks | €0 |
| **Total** | **€0, with one unpriced line** |
| *Workload metrics pushed to Cockpit instead* | +€355 |

The estate figure and the pushed-metrics comparison come from
[capabilities](kapsule-capabilities.md#cost). fr-par list price excluding
VAT, read 14 September 2026.

## Module specification

Most of this lives in the central cluster and the catalog. What the
foundations module owes it:

| Variable | Default | Constraint |
| --- | --- | --- |
| `cockpit_token_enabled` | `true` | creates a `query`-only token, sensitive output |
| `observability_allowed_cidrs` | **none — required** | IP condition on the read-only policy |
| `billing_reader_enabled` | `false` | Organization-scoped, so opt-in |

Absent by decision: alert manager configuration, contacts, preconfigured
alerts, data exports, dashboards — catalog objects, so four clouds share one
definition.

## Sources

Read 14 September 2026.

[Cockpit pricing][price] · [product integration][integration] ·
[supported endpoints][endpoints] · [federate Scaleway metrics][federate] ·
[data exports][exports] · [Cockpit concepts — tokens, data sources][concepts]
· [alert manager][alerts] · [Cockpit limits][limits] ·
[Billing API][billing-api] · [billing concepts and permission
sets][billing-concepts] · [Cost Manager][cost-manager] · [billing
alerts][billing-alerts] · [Organization quotas][quotas].

[price]: https://www.scaleway.com/en/docs/cockpit/reference-content/cockpit-pricing/
[integration]: https://www.scaleway.com/en/docs/cockpit/reference-content/cockpit-product-integration/
[endpoints]: https://www.scaleway.com/en/docs/cockpit/reference-content/cockpit-supported-endpoints/
[federate]: https://www.scaleway.com/en/docs/cockpit/how-to/federate-scaleway-metrics/
[exports]: https://www.scaleway.com/en/docs/cockpit/how-to/manage-data-exports/
[concepts]: https://www.scaleway.com/en/docs/cockpit/concepts/
[alerts]: https://www.scaleway.com/en/docs/cockpit/how-to/enable-alert-manager/
[limits]: https://www.scaleway.com/en/docs/cockpit/reference-content/cockpit-limitations/
[billing-api]: https://www.scaleway.com/en/developers/api/billing/
[billing-concepts]: https://www.scaleway.com/en/docs/billing/concepts/
[cost-manager]: https://www.scaleway.com/en/docs/billing/how-to/use-the-cost-manager/
[billing-alerts]: https://www.scaleway.com/en/docs/billing/how-to/use-billing-alerts/
[quotas]: https://www.scaleway.com/en/docs/organizations-and-projects/additional-content/organization-quotas/
